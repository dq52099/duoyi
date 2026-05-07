import 'package:flutter/material.dart';

class PomodoroTimerRing extends StatelessWidget {
  final double progress;
  final String timeText;
  final Color color;

  const PomodoroTimerRing({
    super.key,
    required this.progress,
    required this.timeText,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 30,
            spreadRadius: 10,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 240,
            height: 240,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 8,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.grey.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timeText,
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w300,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                  color: Theme.of(context).textTheme.headlineSmall?.color,
                ),
              ),
              const SizedBox(height: 8),
              if (progress > 0 && progress < 1.0)
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
