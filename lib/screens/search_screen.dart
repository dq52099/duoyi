import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/global_search.dart';
import '../providers/anniversary_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/note_provider.dart';
import '../providers/todo_provider.dart';
import '../widgets/empty_state.dart';
import 'anniversary_screen.dart';
import 'countdown_screen.dart';
import 'course_schedule_screen.dart';
import 'diary_screen.dart';
import 'goal_screen.dart';
import 'habit_screen.dart';
import 'note_screen.dart';
import 'todo_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = [];
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      final q = v.trim();
      if (!mounted) return;
      if (q.isEmpty) {
        setState(() {
          _hits = [];
          _query = '';
        });
        return;
      }
      final hits = GlobalSearch.run(
        query: q,
        todos: context.read<TodoProvider>().todos,
        habits: context.read<HabitProvider>().habits,
        notes: context.read<NoteProvider>().notes,
        diaries: context.read<DiaryProvider>().entries,
        anniversaries: context.read<AnniversaryProvider>().items,
        countdowns: context.read<CountdownProvider>().items,
        goals: context.read<GoalProvider>().goals,
        courses: context.read<CourseProvider>().courses,
      );
      setState(() {
        _hits = hits;
        _query = q;
      });
    });
  }

  void _open(SearchHit h) {
    switch (h.kind) {
      case SearchKind.todo:
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TodoDetailScreen(todoId: h.sourceId)),
        );
        break;
      case SearchKind.habit:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HabitScreen()),
        );
        break;
      case SearchKind.note:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NoteScreen()),
        );
        break;
      case SearchKind.diary:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DiaryScreen()),
        );
        break;
      case SearchKind.anniversary:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AnniversaryScreen()),
        );
        break;
      case SearchKind.countdown:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CountdownScreen()),
        );
        break;
      case SearchKind.goal:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const GoalScreen()),
        );
        break;
      case SearchKind.course:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CourseScheduleScreen()),
        );
        break;
    }
  }

  Widget _highlight(String text, String q) {
    if (q.isEmpty) return Text(text);
    final lower = text.toLowerCase();
    final qLower = q.toLowerCase();
    final idx = lower.indexOf(qLower);
    if (idx < 0) return Text(text);
    final end = idx + q.length;
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, end),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: '搜索待办 · 习惯 · 笔记 · 日记 · 纪念日 …',
          ),
          onChanged: _onChanged,
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _ctrl.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _query.isEmpty
          ? const EmptyState(
              icon: Icons.search, message: '输入关键字，搜索全部内容')
          : _hits.isEmpty
              ? EmptyState(
                  icon: Icons.sentiment_dissatisfied,
                  message: '没找到 "$_query" 相关结果',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _hits.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (_, i) {
                    final h = _hits[i];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.12),
                        child: Icon(h.icon,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                      title: _highlight(h.title, _query),
                      subtitle: h.subtitle == null || h.subtitle!.isEmpty
                          ? Text(h.kindLabel,
                              style: const TextStyle(fontSize: 11))
                          : Row(children: [
                              Text('${h.kindLabel} · ',
                                  style: const TextStyle(fontSize: 11)),
                              Expanded(
                                child: _highlight(h.subtitle!, _query),
                              ),
                            ]),
                      trailing: h.when == null
                          ? null
                          : Text(
                              '${h.when!.month}/${h.when!.day}',
                              style: const TextStyle(fontSize: 11),
                            ),
                      onTap: () => _open(h),
                    );
                  },
                ),
    );
  }
}
