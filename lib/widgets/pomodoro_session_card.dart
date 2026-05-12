import 'package:flutter/material.dart';
import '../models/pomodoro.dart';
import 'surface_components.dart';

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

    return AppSurfaceCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon(session.type), color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.taskName ?? '$dur分钟${isFocus ? "专注" : "休息"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
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
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (session.whiteNoiseSound != 'none')
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _soundIcon(session.whiteNoiseSound),
                  size: 14,
                  color: Colors.grey,
                ),
              ),
          ],
        ),
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
