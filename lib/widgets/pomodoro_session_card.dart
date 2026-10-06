import 'package:flutter/material.dart';
import '../core/focus_sound_catalog.dart';
import '../core/i18n_date_format.dart';
import '../models/pomodoro.dart';
import '../core/main_ui_copy.dart';
import 'surface_components.dart';

class PomodoroSessionCard extends StatelessWidget {
  final PomodoroSession session;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const PomodoroSessionCard({
    super.key,
    required this.session,
    this.onEdit,
    this.onDelete,
  });

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final dur = session.durationSeconds ~/ 60;
    final time = I18nDateFormat.time(session.startTime);
    final isFocus = session.type == PomodoroType.focus;
    final color = isFocus ? const Color(0xFFE53935) : const Color(0xFF4CAF50);
    final title = session.taskName?.trim().isNotEmpty == true
        ? session.taskName!
        : (MainUiCopy.isEn
              ? '$dur min ${isFocus ? "Focus" : "Break"}'
              : '$dur分钟${isFocus ? "专注" : "休息"}');
    final durationText = MainUiCopy.isEn ? '$dur min' : '$dur 分钟';

    return AppSurfaceCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.16 : 0.10),
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
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.normal,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hourglass_bottom,
                            size: 12,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            durationText,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (session.whiteNoiseSound != 'none')
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(
                    alpha: isDark ? 0.35 : 0.65,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _soundIcon(session.whiteNoiseSound),
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
            if (onEdit != null)
              Tooltip(
                message: MainUiCopy.pomodoroEditRecord,
                child: IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  iconSize: 20,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  color: cs.primary,
                ),
              ),
            if (onDelete != null)
              Tooltip(
                message: MainUiCopy.pomodoroDeleteRecord,
                child: IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  iconSize: 20,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  color: cs.error,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _soundIcon(String sound) {
    final ids = FocusSoundCatalog.trackIdsFor(sound);
    if (ids.length > 1) return Icons.library_music_outlined;
    final single = ids.isEmpty ? sound : ids.first;
    switch (single) {
      case 'rain':
        return Icons.water_drop;
      case 'forest':
        return Icons.park;
      case 'cafe':
        return Icons.local_cafe;
      case 'waves':
        return Icons.waves;
      case 'thunderstorm':
        return Icons.thunderstorm_outlined;
      case 'storm_rain':
        return Icons.storm_outlined;
      case 'night_rain':
        return Icons.nights_stay_outlined;
      case 'fan':
        return Icons.air;
      case 'deep_stream':
        return Icons.water;
      case 'campfire':
        return Icons.local_fire_department_outlined;
      case 'dawn_birds':
        return Icons.wb_twilight_outlined;
      case 'waterfall':
        return Icons.waterfall_chart;
      case 'brook':
        return Icons.stream_outlined;
      case 'river':
        return Icons.water_outlined;
      case 'crickets':
        return Icons.cruelty_free_outlined;
      case 'clock':
        return Icons.schedule;
      case 'keyboard':
        return Icons.keyboard;
      case 'wind':
        return Icons.air;
      case 'train_station':
        return Icons.train;
      case 'classroom':
        return Icons.school;
      case 'pebble_beach':
        return Icons.beach_access;
      case 'mall':
        return Icons.local_mall_outlined;
      case 'restaurant':
        return Icons.restaurant;
      case 'garden_birds':
        return Icons.park;
      case 'country_night':
        return Icons.nights_stay_outlined;
      case 'shallow_river':
        return Icons.water_outlined;
      case 'veranda_rain':
        return Icons.thunderstorm_outlined;
      case 'breeze_birds':
        return Icons.air;
      default:
        return Icons.music_note;
    }
  }
}
