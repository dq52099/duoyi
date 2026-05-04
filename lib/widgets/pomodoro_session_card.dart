import 'package:flutter/material.dart';
import '../models/pomodoro.dart';

class PomodoroSessionCard extends StatelessWidget {
  final PomodoroSession session;

  const PomodoroSessionCard({super.key, required this.session});

  IconData _icon(PomodoroType t) {
    switch (t) {
      case PomodoroType.focus: return Icons.timer;
      case PomodoroType.shortBreak: return Icons.free_breakfast;
      case PomodoroType.longBreak: return Icons.weekend;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dur = session.durationSeconds ~/ 60;
    final time = '${session.startTime.hour.toString().padLeft(2, '0')}:${session.startTime.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        dense: true,
        leading: Icon(_icon(session.type), color: session.type == PomodoroType.focus ? Colors.red.shade400 : Colors.green),
        title: Text(session.taskName ?? '$dur分钟${session.type == PomodoroType.focus ? "专注" : "休息"}', style: const TextStyle(fontSize: 14)),
        subtitle: Text('$time · $dur 分钟', style: const TextStyle(fontSize: 11)),
        trailing: session.whiteNoiseEnabled ? const Icon(Icons.music_note, size: 16, color: Colors.grey) : null,
      ),
    );
  }
}