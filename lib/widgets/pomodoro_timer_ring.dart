import 'package:flutter/material.dart';

class PomodoroTimerRing extends StatelessWidget {
  final double progress;
  final String timeText;
  final Color color;

  const PomodoroTimerRing({super.key, required this.progress, required this.timeText, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220, height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 210, height: 210,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 10,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(timeText, style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w200, fontFamily: 'monospace', letterSpacing: 2)),
        ],
      ),
    );
  }
}