import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/i18n.dart';
import '../core/smart_date_parser.dart';
import '../models/note.dart';
import '../models/todo.dart';
import '../providers/note_provider.dart';
import '../providers/todo_provider.dart';
import '../services/ai_service.dart';
import '../screens/diary_screen.dart';
import '../screens/search_screen.dart';
import 'surface_components.dart';

/// 展开式快速捕获 FAB：3 个子按钮 + 一个搜索入口。
class QuickCaptureFab extends StatefulWidget {
  const QuickCaptureFab({super.key});

  @override
  State<QuickCaptureFab> createState() => _QuickCaptureFabState();
}

class _QuickCaptureFabState extends State<QuickCaptureFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  Future<void> _quickTodo() async {
    _toggle();
    final ctrl = TextEditingController();
    SmartDateParseResult parsed = SmartDateParseResult.empty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: const Text('快速待办'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '一句话描述（如：明天下午3点开会）',
                ),
                onChanged: (v) => setSt(() {
                  parsed = SmartDateParser.parse(v);
                }),
              ),
              if (parsed.isSuccess) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      ctx,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 14,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '识别到：${_formatParsed(parsed)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(I18n.tr('action.add')),
            ),
          ],
        ),
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      if (!mounted) return;
      // 把识别到的日期片段从标题中剥离
      var title = ctrl.text.trim();
      if (parsed.isSuccess && parsed.matchedText.isNotEmpty) {
        title = title.replaceFirst(parsed.matchedText, '').trim();
        if (title.isEmpty) title = ctrl.text.trim();
      }
      context.read<TodoProvider>().addTodo(
        TodoItem(
          title: title,
          date: parsed.dateTime ?? DateTime.now(),
          dueDate: parsed.hasTimeOfDay ? parsed.dateTime : null,
        ),
      );
    }
  }

  String _formatParsed(SmartDateParseResult r) {
    final dt = r.dateTime!;
    final base = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    if (!r.hasTimeOfDay) return base;
    return '$base ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _quickAiTodo() async {
    _toggle();
    final ctrl = TextEditingController();
    var busy = false;
    var error = '';
    var subtasks = <String>[];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: const Text('AI 快捷创建日程'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: '例如：准备周五汇报'),
              ),
              if (error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(error, style: const TextStyle(color: Colors.red)),
              ],
              if (subtasks.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...subtasks.map(
                  (item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.subdirectory_arrow_right),
                    title: Text(item),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(I18n.tr('action.cancel')),
            ),
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      if (ctrl.text.trim().isEmpty) return;
                      setSt(() {
                        busy = true;
                        error = '';
                      });
                      try {
                        final list = await context
                            .read<AiService>()
                            .breakDownTask(ctrl.text.trim());
                        setSt(() => subtasks = list);
                      } catch (_) {
                        setSt(() => error = 'AI 创建失败，请检查 AI 配置');
                      } finally {
                        setSt(() => busy = false);
                      }
                    },
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: const Text('生成'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      if (!mounted) return;
      context.read<TodoProvider>().addTodo(
        TodoItem(
          title: ctrl.text.trim(),
          subtasks: subtasks.map((s) => Subtask(title: s)).toList(),
        ),
      );
    }
  }

  Future<void> _quickNote() async {
    _toggle();
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('随手记'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '写点什么…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(I18n.tr('action.save')),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      if (!mounted) return;
      final now = DateTime.now();
      context.read<NoteProvider>().addOrUpdateNote(
        NoteItem(
          id: now.millisecondsSinceEpoch.toString(),
          content: ctrl.text.trim(),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  void _quickDiary() {
    _toggle();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DiaryEditScreen()),
    );
  }

  void _openSearch() {
    _toggle();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  Widget _mini({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ScaleTransition(
      scale: _ctrl,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Text(label, style: const TextStyle(fontSize: 12)),
            ),
            FloatingActionButton(
              heroTag: label,
              mini: true,
              backgroundColor: color,
              foregroundColor: Colors.white,
              onPressed: onTap,
              child: Icon(icon),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aiEnabled = context.watch<AiService>().enabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open) ...[
          if (aiEnabled)
            _mini(
              icon: Icons.auto_awesome,
              label: 'AI 创建日程',
              color: Colors.purple,
              onTap: _quickAiTodo,
            ),
          _mini(
            icon: Icons.search,
            label: '全局搜索',
            color: Colors.grey,
            onTap: _openSearch,
          ),
          _mini(
            icon: Icons.book_outlined,
            label: '写日记',
            color: const Color(0xFF26A69A),
            onTap: _quickDiary,
          ),
          _mini(
            icon: Icons.edit_note,
            label: '记一笔',
            color: Colors.amber.shade700,
            onTap: _quickNote,
          ),
          _mini(
            icon: Icons.check_circle_outline,
            label: '快速待办',
            color: cs.primary,
            onTap: _quickTodo,
          ),
        ],
        FloatingActionButton(
          heroTag: 'quick_capture',
          onPressed: _toggle,
          child: AnimatedRotation(
            turns: _open ? 0.125 : 0,
            duration: const Duration(milliseconds: 220),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}
