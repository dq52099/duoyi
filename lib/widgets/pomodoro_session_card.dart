import 'package:flutter/material.dart';
import '../models/pomodoro.dart';

class PomodoroSessionCard extends StatelessWidget {
  final PomodoroSession session;

  const PomodoroSessionCard({super.key, required this.session});

  IconData _icon(PomodoroType t) {
    switch (t) {
      case PomodoroType.focus:
        return Icons.timer;
      case PomodoroType.shortBreak:
        return Icons.free_breakfast;
      case PomodoroType.longBreak:
        return Icons.weekend;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dur = session.durationSeconds ~/ 60;
    final time =
        '${session.startTime.hour.toString().padLeft(2, '0')}:${session.startTime.minute.toString().padLeft(2, '0')}';
    final isFocus = session.type == PomodoroType.focus;
    final color = isFocus ? const Color(0xFFE53935) : const Color(0xFF4CAF50);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(_icon(session.type), color: color, size: 20),
        ),
        title: Text(
          session.taskName ?? '$dur分钟${isFocus ? "专注" : "休息"}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                time,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.hourglass_bottom,
                size: 12,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 4),
              Text(
                '$dur 分钟',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        trailing: session.whiteNoiseSound != 'none'
            ? Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _soundIcon(session.whiteNoiseSound),
                  size: 14,
                  color: Colors.grey,
                ),
              )
            : null,
      ),
    );
  }

  IconData _soundIcon(String sound) {
    switch (sound) {
      case 'rain':
        return Icons.water_drop;
      case 'forest':
        return Icons.park;
      case 'cafe':
        return Icons.local_cafe;
      case 'waves':
        return Icons.waves;
      default:
        return Icons.music_note;
    }
  }
}
