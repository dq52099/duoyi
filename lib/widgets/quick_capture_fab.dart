import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../models/todo.dart';
import '../providers/note_provider.dart';
import '../providers/todo_provider.dart';
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('快速待办'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '一句话描述'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      if (!mounted) return;
      context.read<TodoProvider>().addTodo(TodoItem(title: ctrl.text.trim()));
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
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open) ...[
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
