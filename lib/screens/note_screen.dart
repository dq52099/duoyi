import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/note_provider.dart';
import '../models/note.dart';
import '../widgets/empty_state.dart';

class NoteScreen extends StatelessWidget {
  const NoteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NoteProvider>();
    final notes = provider.notes;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('随手记')),
      body: notes.isEmpty
          ? EmptyState(
              icon: Icons.edit_note,
              message: '随时捕捉闪念与灵感',
              actionLabel: '写便签',
              onAction: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NoteEditScreen()),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return Dismissible(
                  key: ValueKey(note.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cs.error,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                    ),
                  ),
                  onDismissed: (_) => provider.deleteNote(note.id),
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NoteEditScreen(note: note),
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (note.preview.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              note.preview,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            '${note.updatedAt.year}-${note.updatedAt.month.toString().padLeft(2, '0')}-${note.updatedAt.day.toString().padLeft(2, '0')} ${note.updatedAt.hour.toString().padLeft(2, '0')}:${note.updatedAt.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NoteEditScreen()),
        ),
        child: const Icon(Icons.edit),
      ),
    );
  }
}

class NoteEditScreen extends StatefulWidget {
  final NoteItem? note;
  const NoteEditScreen({super.key, this.note});

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.note?.content ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _saveAndPop() {
    final text = _ctrl.text.trim();
    if (text.isNotEmpty) {
      final now = DateTime.now();
      context.read<NoteProvider>().addOrUpdateNote(
        NoteItem(
          id: widget.note?.id ?? now.millisecondsSinceEpoch.toString(),
          content: text,
          createdAt: widget.note?.createdAt ?? now,
          updatedAt: now,
        ),
      );
    } else if (widget.note != null) {
      context.read<NoteProvider>().deleteNote(widget.note!.id);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑便签'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _saveAndPop),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextField(
          controller: _ctrl,
          maxLines: null,
          expands: true,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '写点什么...',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
      ),
    );
  }
}
