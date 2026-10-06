import 'package:flutter/material.dart';
import '../core/main_ui_copy.dart';

class PomodoroTimerRing extends StatelessWidget {
  final double progress;
  final String timeText;
  final Color color;
  final double size;
  final bool countUp;

  const PomodoroTimerRing({
    super.key,
    required this.progress,
    required this.timeText,
    required this.color,
    this.size = 220,
    this.countUp = false,
  });

  @override
  Widget build(BuildContext context) {
    final compact = size < 150;
    final timeFontSize = size >= 200
        ? 48.0
        : compact
        ? 32.0
        : 40.0;
    return Container(
      width: size,
      height: size,
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
            width: size - 18,
            height: size - 18,
            child: CircularProgressIndicator(
              value: countUp ? 1.0 : progress,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    timeText,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: timeFontSize,
                      fontWeight: FontWeight.w300,
                      fontFamily: 'monospace',
                      letterSpacing: 0,
                      color: Theme.of(context).textTheme.headlineSmall?.color,
                    ),
                  ),
                ),
              ),
              if (!compact) const SizedBox(height: 8),
              if (!countUp && progress > 0 && !compact)
                Text(
                  MainUiCopy.pomodoroRemainingPercent(
                    (progress.clamp(0.0, 1.0) * 100).round(),
                  ),
                  style: TextStyle(
                    fontSize: progress >= 1.0 ? 14 : 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.58),
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
