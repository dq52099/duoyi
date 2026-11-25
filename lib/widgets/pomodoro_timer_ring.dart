import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/main_ui_copy.dart';

class _VerticalShiftCacheKey {
  final int timeLength;
  final int? percentLength;
  final double size;
  final double textScale;
  final double percentFontSize;
  final TextDirection textDirection;
  final AppLocale locale;

  const _VerticalShiftCacheKey({
    required this.timeLength,
    required this.percentLength,
    required this.size,
    required this.textScale,
    required this.percentFontSize,
    required this.textDirection,
    required this.locale,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _VerticalShiftCacheKey &&
          other.timeLength == timeLength &&
          other.percentLength == percentLength &&
          other.size == size &&
          other.textScale == textScale &&
          other.percentFontSize == percentFontSize &&
          other.textDirection == textDirection &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
    timeLength,
    percentLength,
    size,
    textScale,
    percentFontSize,
    textDirection,
    locale,
  );
}

List<BoxShadow> _pomodoroShadowsFor(Color color) {
  final key = color.toARGB32();
  final existing = PomodoroTimerRing._shadowCache.remove(key);
  if (existing != null) {
    PomodoroTimerRing._shadowCache[key] = existing;
    return existing;
  }
  final shadows = List<BoxShadow>.unmodifiable([
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
  ]);
  if (PomodoroTimerRing._shadowCache.length >=
      PomodoroTimerRing._maxShadowCacheEntries) {
    PomodoroTimerRing._shadowCache.remove(
      PomodoroTimerRing._shadowCache.keys.first,
    );
  }
  PomodoroTimerRing._shadowCache[key] = shadows;
  return shadows;
}

/// Static circular shadow disc for [PomodoroTimerRing], kept separate from
/// per-second progress/text repaints so shadows are not re-rasterized each tick.
class PomodoroTimerRingBackdrop extends StatelessWidget {
  final double size;
  final Color color;
  final Color? surfaceColor;

  const PomodoroTimerRingBackdrop({
    super.key,
    required this.size,
    required this.color,
    this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: surfaceColor ?? Theme.of(context).colorScheme.surface,
          boxShadow: _pomodoroShadowsFor(color),
        ),
      ),
    );
  }
}

class PomodoroTimerRing extends StatelessWidget {
  static const int _maxShiftCacheEntries = 64;
  static const int _maxShadowCacheEntries = 16;
  static final LinkedHashMap<_VerticalShiftCacheKey, double>
  _verticalShiftCache = LinkedHashMap<_VerticalShiftCacheKey, double>();
  static final LinkedHashMap<int, List<BoxShadow>> _shadowCache =
      LinkedHashMap<int, List<BoxShadow>>();

  final double progress;
  final String timeText;
  final Color color;
  final double size;
  final bool countUp;
  final bool showOuterDecoration;

  const PomodoroTimerRing({
    super.key,
    required this.progress,
    required this.timeText,
    required this.color,
    this.size = 220,
    this.countUp = false,
    this.showOuterDecoration = true,
  });

  @visibleForTesting
  static int get verticalShiftCacheLengthForTest => _verticalShiftCache.length;

  @visibleForTesting
  static void clearCachesForTest() {
    _verticalShiftCache.clear();
    _shadowCache.clear();
  }

  static double _resolveVerticalShift({
    required double size,
    required String timeText,
    required double timeFontSize,
    required String percentText,
    required double percentFontSize,
    required TextDirection textDirection,
    required TextScaler textScaler,
  }) {
    final key = _VerticalShiftCacheKey(
      timeLength: timeText.length,
      percentLength: percentText.length,
      size: size,
      textScale: textScaler.scale(1.0),
      percentFontSize: percentFontSize,
      textDirection: textDirection,
      locale: I18n.current,
    );
    final cached = _verticalShiftCache.remove(key);
    if (cached != null) {
      _verticalShiftCache[key] = cached;
      return cached;
    }

    final percentPainter = TextPainter(
      text: TextSpan(
        text: percentText,
        style: TextStyle(
          fontSize: percentFontSize,
          fontWeight: FontWeight.normal,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();

    final strokeInnerRadius = (size - 18) / 2 - 3.0;
    final halfWidth = percentPainter.width / 2;

    final maxSafeY = halfWidth < strokeInnerRadius
        ? math.sqrt(
            strokeInnerRadius * strokeInnerRadius - halfWidth * halfWidth,
          )
        : 0.0;

    final timePainter = TextPainter(
      text: TextSpan(
        text: timeText,
        style: TextStyle(
          fontSize: timeFontSize,
          fontWeight: FontWeight.w300,
          fontFamily: 'monospace',
          letterSpacing: 0,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();

    final maxWidth = size - 28.0;
    final timeScale = timePainter.width > maxWidth
        ? maxWidth / timePainter.width
        : 1.0;
    final scaledTimeHeight = timePainter.height * timeScale;

    final standardColumnHeight = scaledTimeHeight + 8.0 + percentPainter.height;
    final standardBottom = standardColumnHeight / 2;

    var verticalShift = 0.0;
    final deficit = standardBottom - maxSafeY;
    if (deficit > 0) {
      verticalShift = (deficit * 0.75 + 1.0).clamp(0.0, 21.0);
    }
    percentPainter.dispose();
    timePainter.dispose();

    if (_verticalShiftCache.length >= _maxShiftCacheEntries) {
      _verticalShiftCache.remove(_verticalShiftCache.keys.first);
    }
    _verticalShiftCache[key] = verticalShift;
    return verticalShift;
  }

  @override
  Widget build(BuildContext context) {
    final compact = size < 150;
    final timeFontSize = size >= 200
        ? 48.0
        : compact
        ? 32.0
        : 40.0;
    final showPercentage = !countUp && progress > 0 && !compact;
    final percentText = showPercentage
        ? MainUiCopy.pomodoroRemainingPercent(
            (progress.clamp(0.0, 1.0) * 100).round(),
          )
        : null;
    final percentFontSize = progress >= 1.0 ? 14.0 : 16.0;

    double verticalShift = 0.0;
    if (showPercentage && percentText != null) {
      final textScaler = MediaQuery.textScalerOf(context);
      final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
      verticalShift = _resolveVerticalShift(
        size: size,
        timeText: timeText,
        timeFontSize: timeFontSize,
        percentText: percentText,
        percentFontSize: percentFontSize,
        textDirection: textDirection,
        textScaler: textScaler,
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ringContent = RepaintBoundary(
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
              backgroundColor: cs.surfaceContainerHighest.withValues(
                alpha: 0.4,
              ),
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
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: theme.textTheme.headlineSmall?.color,
                    ),
                  ),
                ),
              ),
              if (!compact) const SizedBox(height: 8),
              if (showPercentage && percentText != null)
                verticalShift > 0
                    ? Transform.translate(
                        offset: Offset(0, -verticalShift),
                        child: Text(
                          percentText,
                          style: TextStyle(
                            fontSize: percentFontSize,
                            color: cs.onSurface,
                            fontWeight: FontWeight.normal,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      )
                    : Text(
                        percentText,
                        style: TextStyle(
                          fontSize: percentFontSize,
                          color: cs.onSurface,
                          fontWeight: FontWeight.normal,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
            ],
          ),
        ],
      ),
    );

    if (!showOuterDecoration) {
      return SizedBox(width: size, height: size, child: ringContent);
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: PomodoroTimerRingBackdrop(
              size: size,
              color: color,
              surfaceColor: cs.surface,
            ),
          ),
          ringContent,
        ],
      ),
    );
  }
}
