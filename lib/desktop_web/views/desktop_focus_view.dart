import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/focus_report.dart';
import '../../core/focus_report_presentation.dart';
import '../../core/focus_room_ui_copy.dart';
import '../../core/focus_sound_catalog.dart';
import '../../core/i18n.dart';
import '../../core/i18n_date_format.dart';
import '../../models/focus_room.dart';
import '../../models/pomodoro.dart';
import '../../models/todo.dart';
import '../../providers/auth_provider.dart';
import '../../providers/custom_focus_sound_provider.dart';
import '../../providers/focus_room_provider.dart';
import '../../providers/pomodoro_provider.dart';
import '../../providers/todo_provider.dart';
import '../../screens/pomodoro_screen.dart';
import '../../services/focus_sound_service.dart';
import '../desktop_web_nav.dart';
import '../desktop_web_tokens.dart';

enum _FocusStudioMode { timer, history, rooms }

T? _maybeWatch<T extends Object>(BuildContext context, {bool listen = true}) {
  try {
    return Provider.of<T>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}

String _formatClockSeconds(int totalSeconds) {
  final safe = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final seconds = safe % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _formatMinutesSummary(int totalMinutes, AppLocale locale) {
  final isEn = locale == AppLocale.en;
  if (totalMinutes < 60) {
    return isEn ? '$totalMinutes min' : '$totalMinutes 分钟';
  }
  final hours = totalMinutes ~/ 60;
  final mins = totalMinutes % 60;
  if (mins == 0) {
    return isEn ? '${hours}h' : '$hours 小时';
  }
  return isEn ? '${hours}h ${mins}m' : '$hours小时$mins分';
}

/// Refactored Desktop 2-Pane Focus Studio that stays embedded inside the
/// persistent Desktop Web workspace shell.
class DesktopFocusView extends StatefulWidget {
  final DesktopWebNavController? controller;
  final void Function(DesktopWebDestination destination)? onNavigate;

  const DesktopFocusView({
    super.key,
    this.controller,
    this.onNavigate,
  });

  @override
  State<DesktopFocusView> createState() => _DesktopFocusViewState();
}

class _DesktopFocusViewState extends State<DesktopFocusView>
    with SingleTickerProviderStateMixin {
  static const List<int> _presetMinutes = <int>[15, 25, 30, 45, 60, 90];

  _FocusStudioMode _mode = _FocusStudioMode.timer;
  FocusSoundCategory _selectedSoundCategory = FocusSoundCategory.rain;
  FocusReportPeriod _reportPeriod = FocusReportPeriod.week;
  bool _showMarkdownReport = false;
  int _roomLeaderboardSegment = 0; // 0: active room, 1: friends, 2: global

  final TextEditingController _taskCtrl = TextEditingController();
  final FocusNode _taskFocus = FocusNode();
  final GlobalKey _soundCardKey = GlobalKey();

  late final AnimationController _haloCtrl;
  DesktopWebNavController? _attachedController;
  FocusRoomProvider? _realtimeRoomsProvider;
  bool _realtimeWatching = false;
  bool _isAuditioningSound = false;
  bool _ambientMixMode = false;
  String? _lastSyncedTaskName;
  String? _lastTopBarSignature;

  @override
  void initState() {
    super.initState();
    _haloCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = widget.controller ?? DesktopWebScope.maybeOf(context);
    if (!identical(_attachedController, nextController)) {
      _attachedController = nextController;
    }
    _syncRealtimeRooms();
  }

  @override
  void dispose() {
    if (_realtimeWatching) {
      _realtimeRoomsProvider?.stopRealtimeRankings();
    }
    _haloCtrl.dispose();
    _taskCtrl.dispose();
    _taskFocus.dispose();
    super.dispose();
  }

  void _syncRealtimeRooms() {
    final roomsProvider = _maybeWatch<FocusRoomProvider>(
      context,
      listen: false,
    );
    final shouldWatch =
        _mode == _FocusStudioMode.rooms && roomsProvider != null;
    if (shouldWatch && !_realtimeWatching) {
      _realtimeRoomsProvider = roomsProvider;
      _realtimeWatching = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_realtimeWatching) return;
        _realtimeRoomsProvider?.watchRealtimeRankings();
      });
    } else if (!shouldWatch && _realtimeWatching) {
      _realtimeWatching = false;
      _realtimeRoomsProvider?.stopRealtimeRankings();
      _realtimeRoomsProvider = null;
    }
  }

  void _syncHaloAnimation(bool isRunning) {
    if (isRunning && !_haloCtrl.isAnimating) {
      _haloCtrl.repeat(reverse: true);
    } else if (!isRunning && _haloCtrl.isAnimating) {
      _haloCtrl.stop();
      _haloCtrl.value = 0.0;
    }
  }

  void _syncTaskController(PomodoroState state) {
    final nextTask = state.taskName ?? '';
    if (!_taskFocus.hasFocus && _lastSyncedTaskName != nextTask) {
      _lastSyncedTaskName = nextTask;
      if (_taskCtrl.text != nextTask) {
        _taskCtrl.text = nextTask;
      }
    }
  }

  void _publishTopBarSpec(AppLocale locale, PomodoroProvider? provider) {
    final controller = _attachedController;
    if (controller == null || provider == null) return;
    final isEn = locale == AppLocale.en;
    final st = provider.state;
    final status = st.isRunning
        ? (isEn
              ? 'Focusing · ${_formatClockSeconds(st.remainingSeconds)}'
              : '专注进行中 · ${_formatClockSeconds(st.remainingSeconds)}')
        : (isEn
              ? '${provider.sessionCountToday} sessions today'
              : '今日已完成 ${provider.sessionCountToday} 次专注');
    final sig = '${locale.name}|$status';
    if (sig == _lastTopBarSignature) return;
    _lastTopBarSignature = sig;
    controller.setTopBarSpec(
      DesktopWebDestination.focus,
      DesktopTopBarSpec(
        title: isEn ? 'Focus Studio' : '番茄专注',
        subtitle: status,
        showQuickSearch: true,
        showQuickCreate: true,
      ),
    );
  }

  Color _phaseColor(PomodoroState state, DesktopWebTokens tokens) {
    return switch (state.type) {
      PomodoroType.focus => tokens.accent,
      PomodoroType.shortBreak => tokens.success,
      PomodoroType.longBreak => tokens.info,
    };
  }

  String _phaseLabel(PomodoroState state, AppLocale locale) {
    final isEn = locale == AppLocale.en;
    if (state.isCountUp) {
      return isEn ? 'Count-Up Focus' : '正计时专注';
    }
    return switch (state.type) {
      PomodoroType.focus => isEn ? 'Deep Focus' : '深度专注',
      PomodoroType.shortBreak => isEn ? 'Short Break' : '短休息',
      PomodoroType.longBreak => isEn ? 'Long Break' : '长休息',
    };
  }

  String _localizedSoundLabel(
    String soundId,
    CustomFocusSoundProvider? customSounds,
    AppLocale locale,
  ) {
    if (soundId == FocusSoundCatalog.none) {
      return locale == AppLocale.en ? 'Silence' : '无白噪音';
    }
    if (customSounds != null && customSounds.isCustomSound(soundId)) {
      return customSounds.labelFor(soundId, locale: locale);
    }
    return FocusSoundCatalog.labelFor(soundId, locale: locale);
  }

  Future<void> _selectSound(
    PomodoroProvider provider,
    String soundId,
  ) async {
    if ((_ambientMixMode || provider.hasMultiTrackMix) &&
        soundId != FocusSoundCatalog.none) {
      await provider.toggleMixerTrack(soundId);
      if (mounted) {
        setState(() => _isAuditioningSound = provider.isMixerAuditioning);
      }
      return;
    }
    await provider.selectSingleAmbientTrack(soundId);
    if (!mounted) return;
    if (soundId == FocusSoundCatalog.none) {
      setState(() {
        _ambientMixMode = false;
        _isAuditioningSound = false;
      });
      try {
        await FocusSoundService.instance.stop();
      } catch (_) {}
    } else if (!provider.state.isRunning) {
      setState(() => _isAuditioningSound = FocusSoundService.instance.isPlaying);
    }
  }

  Future<void> _toggleSoundAudition(PomodoroProvider provider) async {
    if (provider.hasMultiTrackMix || _ambientMixMode) {
      final playing = await provider.toggleMixerAudition();
      if (mounted) setState(() => _isAuditioningSound = playing);
      return;
    }
    final current = provider.state.whiteNoiseSound;
    if (current == FocusSoundCatalog.none) return;
    try {
      if (_isAuditioningSound || FocusSoundService.instance.isPlaying) {
        await FocusSoundService.instance.stop();
        if (mounted) setState(() => _isAuditioningSound = false);
      } else {
        await FocusSoundService.instance.setVolume(
          provider.config.focusSoundVolume,
        );
        final started = await FocusSoundService.instance.play(current);
        if (mounted) setState(() => _isAuditioningSound = started);
      }
    } catch (_) {
      if (mounted) setState(() => _isAuditioningSound = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final tokens = DesktopWebTokens.of(context);
        final pomodoro = _maybeWatch<PomodoroProvider>(context);
        final todos = _maybeWatch<TodoProvider>(context);
        final customSounds = _maybeWatch<CustomFocusSoundProvider>(context);
        final focusRooms = _maybeWatch<FocusRoomProvider>(context);
        final auth = _maybeWatch<AuthProvider>(context);

        if (pomodoro == null) {
          return Center(
            child: Text(
              locale == AppLocale.en
                  ? 'Focus provider unavailable'
                  : '专注服务暂未就绪',
              style: tokens.bodyMutedStyle,
            ),
          );
        }

        final state = pomodoro.state;
        _syncHaloAnimation(state.isRunning);
        _syncTaskController(state);
        _publishTopBarSpec(locale, pomodoro);

        return Column(
          children: [
            _buildModeToolbar(
              tokens: tokens,
              locale: locale,
              provider: pomodoro,
              rooms: focusRooms,
            ),
            Expanded(
              child: switch (_mode) {
                _FocusStudioMode.timer => _buildStudioPane(
                  tokens: tokens,
                  locale: locale,
                  provider: pomodoro,
                  todos: todos,
                  customSounds: customSounds,
                ),
                _FocusStudioMode.history => _buildHistoryView(
                  tokens: tokens,
                  locale: locale,
                  provider: pomodoro,
                ),
                _FocusStudioMode.rooms => _buildStudyRoomsView(
                  tokens: tokens,
                  locale: locale,
                  provider: pomodoro,
                  roomsProvider: focusRooms,
                  auth: auth,
                ),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildModeToolbar({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required PomodoroProvider provider,
    required FocusRoomProvider? rooms,
  }) {
    final isEn = locale == AppLocale.en;
    final activeRoom = rooms?.activeRoom;
    final defaultMinutes = provider.effectiveFocusDuration ~/ 60;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.topbarBackground,
        border: Border(
          bottom: BorderSide(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
      ),
      child: Row(
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                height: 32,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: tokens.mutedSurface,
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusSm,
                  ),
                  border: Border.all(
                    color: tokens.hairlineBorder,
                    width: DesktopWebTokens.hairlineWidth,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FocusModeTab(
                      icon: Icons.timer_outlined,
                      label: isEn ? 'Focus Timer' : '专注计时',
                      selected: _mode == _FocusStudioMode.timer,
                      tokens: tokens,
                      onTap: () {
                        setState(() => _mode = _FocusStudioMode.timer);
                        _syncRealtimeRooms();
                      },
                    ),
                    _FocusModeTab(
                      icon: Icons.bar_chart_rounded,
                      label: isEn ? 'Focus History' : '专注记录',
                      selected: _mode == _FocusStudioMode.history,
                      tokens: tokens,
                      onTap: () {
                        setState(() => _mode = _FocusStudioMode.history);
                        _syncRealtimeRooms();
                      },
                    ),
                    _FocusModeTab(
                      icon: Icons.groups_outlined,
                      label: isEn ? 'Study Rooms' : '专注自习室',
                      selected: _mode == _FocusStudioMode.rooms,
                      tokens: tokens,
                      onTap: () {
                        setState(() => _mode = _FocusStudioMode.rooms);
                        _syncRealtimeRooms();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Spacer(),
          if (activeRoom != null) ...[
            InkWell(
              onTap: () {
                setState(() => _mode = _FocusStudioMode.rooms);
                _syncRealtimeRooms();
              },
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: tokens.mutedSurface,
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusPill,
                  ),
                  border: Border.all(
                    color: tokens.hairlineBorder,
                    width: DesktopWebTokens.hairlineWidth,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: tokens.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        activeRoom.nameFor(locale),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.captionStyle.copyWith(
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
            ),
            child: Text(
              isEn ? 'Default $defaultMinutes min' : '默认 $defaultMinutes 分钟',
              style: tokens.captionStyle.copyWith(color: tokens.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudioPane({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required PomodoroProvider provider,
    required TodoProvider? todos,
    required CustomFocusSoundProvider? customSounds,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTimerStage(
                  tokens: tokens,
                  locale: locale,
                  provider: provider,
                  customSounds: customSounds,
                ),
                const SizedBox(height: 16),
                _buildStudioRightPanel(
                  tokens: tokens,
                  locale: locale,
                  provider: provider,
                  todos: todos,
                  customSounds: customSounds,
                  scrollable: false,
                ),
              ],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: _buildTimerStage(
                    tokens: tokens,
                    locale: locale,
                    provider: provider,
                    customSounds: customSounds,
                  ),
                ),
              ),
            ),
            VerticalDivider(
              width: DesktopWebTokens.hairlineWidth,
              thickness: DesktopWebTokens.hairlineWidth,
              color: tokens.hairlineBorder,
            ),
            SizedBox(
              width: DesktopWebTokens.focusInspectorWidth,
              child: _buildStudioRightPanel(
                tokens: tokens,
                locale: locale,
                provider: provider,
                todos: todos,
                customSounds: customSounds,
                scrollable: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimerStage({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required PomodoroProvider provider,
    required CustomFocusSoundProvider? customSounds,
  }) {
    final isEn = locale == AppLocale.en;
    final state = provider.state;
    final phaseColor = _phaseColor(state, tokens);
    final selectedMinutes = provider.effectiveFocusDuration ~/ 60;
    final soundLabel = _localizedSoundLabel(
      state.whiteNoiseSound,
      customSounds,
      locale,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Phase indicator badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: phaseColor.withValues(alpha: tokens.isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
              border: Border.all(
                color: phaseColor.withValues(alpha: 0.30),
                width: DesktopWebTokens.hairlineWidth,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: state.isRunning ? phaseColor : tokens.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _phaseLabel(state, locale),
                  style: tokens.captionStyle.copyWith(
                    fontSize: 12.5,
                    color: phaseColor,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Serene breathing circular progress timer
          ValueListenableBuilder<int>(
            valueListenable: provider.timerTicks,
            builder: (context, _, _) {
              final st = provider.state;
              final progress = st.isCountUp
                  ? ((st.remainingSeconds % 60) / 60.0)
                  : st.progress.clamp(0.0, 1.0);
              final timeText = _formatClockSeconds(st.remainingSeconds);
              final subtitleText = st.isCountUp
                  ? (isEn ? 'ELAPSED' : '已持续专注')
                  : '${(progress * 100).round()}%';

              return _DesktopTimerRing(
                size: 268,
                progress: progress,
                timeText: timeText,
                subtitleText: subtitleText,
                accentColor: phaseColor,
                isRunning: st.isRunning,
                isCountUp: st.isCountUp,
                haloAnimation: _haloCtrl,
                tokens: tokens,
              );
            },
          ),

          const SizedBox(height: 20),

          // Active task & sound status bar (independent task-focus & sound targets)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: tokens.panelSurface,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
              border: Border.all(
                color: tokens.hairlineBorder,
                width: DesktopWebTokens.hairlineWidth,
              ),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                InkWell(
                  onTap: () => _taskFocus.requestFocus(),
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusPill,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.task_alt_outlined,
                          size: 15,
                          color: state.taskName != null
                              ? phaseColor
                              : tokens.textMuted,
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            state.taskName?.trim().isNotEmpty == true
                                ? state.taskName!
                                : (isEn
                                      ? 'Select or type focus task →'
                                      : '点击选择或输入专注任务 →'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.bodyMutedStyle.copyWith(
                              color: state.taskName != null
                                  ? tokens.textPrimary
                                  : tokens.textMuted,
                            ),
                          ),
                        ),
                        if (state.tag?.trim().isNotEmpty == true) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.accentSoft,
                              borderRadius: BorderRadius.circular(
                                DesktopWebTokens.radiusPill,
                              ),
                              border: Border.all(
                                color: tokens.accentBorder,
                                width: DesktopWebTokens.hairlineWidth,
                              ),
                            ),
                            child: Text(
                              '#${state.tag}',
                              style: tokens.captionStyle.copyWith(
                                color: tokens.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  width: DesktopWebTokens.hairlineWidth,
                  height: 14,
                  color: tokens.hairlineBorder,
                ),
                Builder(
                  builder: (context) {
                    final hasSound =
                        state.whiteNoiseSound != FocusSoundCatalog.none ||
                        provider.hasMultiTrackMix;
                    final isPlaying =
                        _isAuditioningSound || provider.isMixerAuditioning;
                    return Tooltip(
                      message: hasSound
                          ? (isPlaying
                                ? (isEn ? 'Stop sound preview' : '停止试听白噪音')
                                : (isEn ? 'Preview ambient sound' : '试听白噪音'))
                          : (isEn ? 'Choose ambient sound' : '选择白噪音'),
                      child: InkWell(
                        onTap: () {
                          if (hasSound) {
                            _toggleSoundAudition(provider);
                          } else {
                            final ctx = _soundCardKey.currentContext;
                            if (ctx != null) {
                              Scrollable.ensureVisible(
                                ctx,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                              );
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(
                          DesktopWebTokens.radiusPill,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                !hasSound
                                    ? Icons.volume_off_outlined
                                    : Icons.graphic_eq_rounded,
                                size: 15,
                                color: !hasSound ? tokens.textMuted : phaseColor,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                soundLabel,
                                style: tokens.captionStyle.copyWith(
                                  color: !hasSound
                                      ? tokens.textMuted
                                      : tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Duration Presets + Count-Up toggle
          Tooltip(
            message: state.isRunning
                ? (isEn
                      ? 'Pause timer to change duration mode'
                      : '暂停计时后可切换时长预设')
                : '',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final mins in _presetMinutes)
                  _PresetDurationChip(
                    label: isEn ? '${mins}m' : '$mins 分钟',
                    selected: !state.isCountUp && selectedMinutes == mins,
                    tokens: tokens,
                    accentColor: phaseColor,
                    enabled: !state.isRunning,
                    onTap: () {
                      if (state.isCountUp) {
                        provider.setCountUpMode(false);
                      }
                      provider.setFocusDuration(mins * 60);
                    },
                  ),
                _PresetDurationChip(
                  label: isEn ? 'Count-Up' : '正计时',
                  selected: state.isCountUp,
                  tokens: tokens,
                  accentColor: phaseColor,
                  enabled: !state.isRunning,
                    onTap: () => provider.setCountUpMode(true),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Tactile transport controls
          ValueListenableBuilder<int>(
            valueListenable: provider.timerTicks,
            builder: (context, _, _) {
              final st = provider.state;
              final canFinishEarly =
                  st.type == PomodoroType.focus &&
                  (st.isCountUp
                      ? st.remainingSeconds > 0
                      : st.remainingSeconds < st.totalSeconds);

              return Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: provider.resetTimer,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      side: BorderSide(
                        color: tokens.hairlineBorder,
                        width: DesktopWebTokens.hairlineWidth,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          DesktopWebTokens.radiusPill,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: Text(isEn ? 'Reset' : '重置'),
                  ),
                  FilledButton.icon(
                    onPressed: provider.toggleTimer,
                    style: FilledButton.styleFrom(
                      backgroundColor: phaseColor,
                      foregroundColor: tokens.accentForeground,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          DesktopWebTokens.radiusPill,
                        ),
                      ),
                    ),
                    icon: Icon(
                      st.isRunning
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 22,
                    ),
                    label: Text(
                      st.isRunning
                          ? (isEn ? 'Pause' : '暂停')
                          : (isEn ? 'Start Focus' : '开始专注'),
                      style: tokens.bodyStyle.copyWith(
                        fontSize: 15,
                        color: tokens.accentForeground,
                      ),
                    ),
                  ),
                  if (canFinishEarly)
                    FilledButton.tonalIcon(
                      onPressed: provider.finishCurrentSession,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            DesktopWebTokens.radiusPill,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 17),
                      label: Text(isEn ? 'Finish & Save' : '结束并记录'),
                    ),
                  OutlinedButton.icon(
                    onPressed: provider.skipSession,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      side: BorderSide(
                        color: tokens.hairlineBorder,
                        width: DesktopWebTokens.hairlineWidth,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          DesktopWebTokens.radiusPill,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.skip_next_rounded, size: 17),
                    label: Text(isEn ? 'Skip' : '跳过'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStudioRightPanel({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required PomodoroProvider provider,
    required TodoProvider? todos,
    required CustomFocusSoundProvider? customSounds,
    required bool scrollable,
  }) {
    final children = <Widget>[
      _buildTaskBindingCard(
        tokens: tokens,
        locale: locale,
        provider: provider,
        todos: todos,
      ),
      const SizedBox(height: 12),
      _buildDailyGoalRingCard(
        tokens: tokens,
        locale: locale,
        provider: provider,
      ),
      const SizedBox(height: 12),
      _buildWhiteNoiseCard(
        tokens: tokens,
        locale: locale,
        provider: provider,
        customSounds: customSounds,
      ),
      const SizedBox(height: 12),
      _buildTodayStatsCard(
        tokens: tokens,
        locale: locale,
        provider: provider,
      ),
    ];

    if (!scrollable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }

    return Container(
      color: tokens.isLiquidGlass
          ? tokens.sidebarBackground
          : tokens.sidebarBackground.withValues(alpha: 0.72),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: children,
      ),
    );
  }

  Widget _buildTaskBindingCard({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required PomodoroProvider provider,
    required TodoProvider? todos,
  }) {
    final isEn = locale == AppLocale.en;
    final state = provider.state;
    final activeTodos = todos?.activeTodos ?? const <TodoItem>[];
    final previewTodos = activeTodos.take(5).toList(growable: false);
    final tagPresets = FocusRoomUiCopy.taskPresets(locale);

    return DesktopPanelCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.task_alt_outlined, size: 16, color: tokens.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isEn ? 'Focus Task' : '本轮专注任务',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.cardTitleStyle.copyWith(fontSize: 14),
                ),
              ),
              if (widget.onNavigate != null || _attachedController != null)
                InkWell(
                  onTap: () {
                    if (widget.onNavigate != null) {
                      widget.onNavigate!(DesktopWebDestination.todo);
                    } else {
                      _attachedController?.navigateTo(
                        DesktopWebDestination.todo,
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      isEn ? 'All tasks →' : '全部待办 →',
                      style: tokens.captionStyle.copyWith(color: tokens.accent),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _taskCtrl,
            focusNode: _taskFocus,
            style: tokens.bodyStyle.copyWith(fontSize: 13),
            onChanged: (value) {
              final trimmed = value.trim();
              _lastSyncedTaskName = trimmed;
              provider.setTaskName(trimmed.isEmpty ? null : trimmed);
            },
            decoration: InputDecoration(
              hintText: isEn
                  ? 'Type custom focus task...'
                  : '输入自定义专注任务名...',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              suffixIcon: state.taskName != null && state.taskName!.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 15),
                      onPressed: () {
                        _taskCtrl.clear();
                        _lastSyncedTaskName = '';
                        provider.setTaskName(null);
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final preset in tagPresets.take(5))
                _FocusTagPill(
                  label: '#$preset',
                  selected: state.tag == preset,
                  tokens: tokens,
                  onTap: () {
                    final next = state.tag == preset ? null : preset;
                    provider.setTag(next);
                  },
                ),
            ],
          ),
          if (previewTodos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              isEn ? 'PICK FROM PENDING TASKS' : '从待办清单中选择',
              style: tokens.sectionHeaderStyle,
            ),
            const SizedBox(height: 6),
            for (final todo in previewTodos)
              DesktopHoverTile(
                selected: state.taskName == todo.title,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                onTap: () {
                  final next = state.taskName == todo.title ? null : todo.title;
                  _lastSyncedTaskName = next ?? '';
                  _taskCtrl.text = _lastSyncedTaskName!;
                  provider.setTaskName(next);
                },
                child: Row(
                  children: [
                    Icon(
                      state.taskName == todo.title
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 15,
                      color: state.taskName == todo.title
                          ? tokens.accent
                          : tokens.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        todo.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.bodyStyle.copyWith(
                          fontSize: 12.5,
                          color: state.taskName == todo.title
                              ? tokens.accent
                              : tokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildWhiteNoiseCard({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required PomodoroProvider provider,
    required CustomFocusSoundProvider? customSounds,
  }) {
    final isEn = locale == AppLocale.en;
    final state = provider.state;
    final volume = provider.config.focusSoundVolume;
    final selectedId = state.whiteNoiseSound;
    final selectedGroup = FocusSoundCatalog.groupedOptions.firstWhere(
      (g) => g.category == _selectedSoundCategory,
      orElse: () => FocusSoundCatalog.groupedOptions.first,
    );

    return DesktopPanelCard(
      key: _soundCardKey,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.headphones_outlined, size: 16, color: tokens.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isEn ? 'Ambient Soundscape' : '白噪音氛围',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.cardTitleStyle.copyWith(fontSize: 14),
                ),
              ),
              InkWell(
                key: const ValueKey('desktop_focus_mixer_toggle'),
                onTap: () => setState(() => _ambientMixMode = !_ambientMixMode),
                borderRadius: BorderRadius.circular(
                  DesktopWebTokens.radiusPill,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (_ambientMixMode || provider.hasMultiTrackMix)
                        ? tokens.accentSoft
                        : tokens.mutedSurface,
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusPill,
                    ),
                    border: Border.all(
                      color: (_ambientMixMode || provider.hasMultiTrackMix)
                          ? tokens.accentBorder
                          : Colors.transparent,
                      width: DesktopWebTokens.hairlineWidth,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.layers_outlined,
                        size: 13,
                        color: (_ambientMixMode || provider.hasMultiTrackMix)
                            ? tokens.accent
                            : tokens.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        provider.hasMultiTrackMix
                            ? (isEn
                                  ? 'Mix (${provider.ambientMixerTracks.length})'
                                  : '混音 (${provider.ambientMixerTracks.length})')
                            : (isEn ? 'Mix' : '多轨混音'),
                        style: tokens.captionStyle.copyWith(
                          fontSize: 11,
                          color: (_ambientMixMode || provider.hasMultiTrackMix)
                              ? tokens.accent
                              : tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (selectedId != FocusSoundCatalog.none ||
                  provider.ambientMixerTracks.isNotEmpty) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _toggleSoundAudition(provider),
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusPill,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: (_isAuditioningSound || provider.isMixerAuditioning)
                          ? tokens.accentSoft
                          : tokens.mutedSurface,
                      borderRadius: BorderRadius.circular(
                        DesktopWebTokens.radiusPill,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          (_isAuditioningSound || provider.isMixerAuditioning)
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          size: 14,
                          color: (_isAuditioningSound ||
                                  provider.isMixerAuditioning)
                              ? tokens.accent
                              : tokens.textPrimary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          (_isAuditioningSound || provider.isMixerAuditioning)
                              ? (isEn ? 'Stop' : '停止')
                              : (isEn ? 'Play' : '试听'),
                          style: tokens.captionStyle.copyWith(
                            fontSize: 11,
                            color: (_isAuditioningSound ||
                                    provider.isMixerAuditioning)
                                ? tokens.accent
                                : tokens.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // 5 Categories + Silence pill
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              InkWell(
                onTap: () => _selectSound(provider, FocusSoundCatalog.none),
                borderRadius: BorderRadius.circular(
                  DesktopWebTokens.radiusPill,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: selectedId == FocusSoundCatalog.none
                        ? tokens.accentSoft
                        : tokens.mutedSurface,
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusPill,
                    ),
                    border: Border.all(
                      color: selectedId == FocusSoundCatalog.none
                          ? tokens.accentBorder
                          : tokens.hairlineBorder,
                      width: DesktopWebTokens.hairlineWidth,
                    ),
                  ),
                  child: Text(
                    isEn ? 'Off' : '静音',
                    style: tokens.captionStyle.copyWith(
                      fontSize: 11.5,
                      color: selectedId == FocusSoundCatalog.none
                          ? tokens.accent
                          : tokens.textSecondary,
                    ),
                  ),
                ),
              ),
              for (final group in FocusSoundCatalog.groupedOptions)
                InkWell(
                  onTap: () => setState(
                    () => _selectedSoundCategory = group.category,
                  ),
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusPill,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _selectedSoundCategory == group.category
                          ? tokens.selectedSurface
                          : tokens.mutedSurface,
                      borderRadius: BorderRadius.circular(
                        DesktopWebTokens.radiusPill,
                      ),
                      border: Border.all(
                        color: _selectedSoundCategory == group.category
                            ? tokens.accentBorder
                            : tokens.hairlineBorder,
                        width: DesktopWebTokens.hairlineWidth,
                      ),
                    ),
                    child: Text(
                      group.category.displayLabel(locale: locale),
                      style: tokens.captionStyle.copyWith(
                        fontSize: 11.5,
                        color: _selectedSoundCategory == group.category
                            ? tokens.accent
                            : tokens.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Sound tracks in active category
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final opt in selectedGroup.options)
                Builder(
                  builder: (_) {
                    final isTrackActive = (_ambientMixMode ||
                            provider.hasMultiTrackMix)
                        ? provider.ambientMixerTracks.containsKey(opt.id)
                        : selectedId == opt.id;
                    return InkWell(
                      onTap: () => _selectSound(provider, opt.id),
                      borderRadius: BorderRadius.circular(
                        DesktopWebTokens.radiusSm,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isTrackActive
                              ? tokens.accentSoft
                              : tokens.mutedSurface,
                          borderRadius: BorderRadius.circular(
                            DesktopWebTokens.radiusSm,
                          ),
                          border: Border.all(
                            color: isTrackActive
                                ? tokens.accentBorder
                                : tokens.hairlineBorder,
                            width: DesktopWebTokens.hairlineWidth,
                          ),
                        ),
                        child: Text(
                          opt.displayLabel(locale: locale),
                          style: tokens.captionStyle.copyWith(
                            fontSize: 11.5,
                            color: isTrackActive
                                ? tokens.accent
                                : tokens.textPrimary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          if (_ambientMixMode || provider.hasMultiTrackMix) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('desktop_focus_mixer_tracks'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tokens.mutedSurface,
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
                border: Border.all(
                  color: tokens.hairlineBorder,
                  width: DesktopWebTokens.hairlineWidth,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isEn
                              ? 'Active Mix (${provider.ambientMixerTracks.length}/${PomodoroProvider.maxAmbientMixerTracks})'
                              : '混音轨道 (${provider.ambientMixerTracks.length}/${PomodoroProvider.maxAmbientMixerTracks})',
                          style: tokens.captionStyle.copyWith(
                            color: tokens.accent,
                          ),
                        ),
                      ),
                      if (provider.ambientMixerTracks.isNotEmpty)
                        InkWell(
                          onTap: () => provider.clearMixerTracks(),
                          child: Text(
                            isEn ? 'Clear' : '清空',
                            style: tokens.captionStyle.copyWith(
                              color: tokens.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (provider.ambientMixerTracks.isEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      isEn
                          ? 'Click tracks above to blend 2–4 layers with independent volume.'
                          : '点击上方音轨标签即可叠加 2–4 条环境音轨并独立调节音量。',
                      style: tokens.captionStyle.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  ] else
                    for (final entry in provider.ambientMixerTracks.entries)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 74,
                              child: Text(
                                FocusSoundCatalog.labelFor(
                                  entry.key,
                                  locale: locale,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tokens.captionStyle,
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2.5,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 5,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 10,
                                  ),
                                ),
                                child: Slider(
                                  value: entry.value.clamp(0.1, 1.0),
                                  min: 0.1,
                                  max: 1.0,
                                  onChanged: (v) =>
                                      provider.setMixerTrackVolume(entry.key, v),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 34,
                              child: Text(
                                '${(entry.value * 100).round()}%',
                                textAlign: TextAlign.right,
                                style: tokens.captionStyle.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => provider.toggleMixerTrack(entry.key),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 13,
                                  color: tokens.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ],

          if (customSounds != null && customSounds.sounds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final sound in customSounds.sounds)
                  InkWell(
                    onTap: () => _selectSound(provider, sound.id),
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusSm,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: selectedId == sound.id
                            ? tokens.accentSoft
                            : tokens.mutedSurface,
                        borderRadius: BorderRadius.circular(
                          DesktopWebTokens.radiusSm,
                        ),
                      ),
                      child: Text(
                        customSounds.labelFor(sound.id, locale: locale),
                        style: tokens.captionStyle.copyWith(
                          color: selectedId == sound.id
                              ? tokens.accent
                              : tokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.volume_down_rounded,
                size: 16,
                color: tokens.textMuted,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Slider(
                    value: volume.clamp(
                      FocusSoundService.minimumAudibleVolume,
                      1.0,
                    ),
                    min: FocusSoundService.minimumAudibleVolume,
                    max: 1.0,
                    onChanged: (v) {
                      provider.setFocusSoundVolume(v, preview: false);
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${(volume * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: tokens.captionStyle.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          if (!kIsWeb && customSounds != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final imported = await customSounds.importAudio();
                  if (imported != null && mounted) {
                    await _selectSound(provider, imported.id);
                  }
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.audio_file_outlined, size: 14),
                label: Text(
                  isEn ? 'Import audio' : '导入本地音频',
                  style: tokens.captionStyle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDailyGoalRingCard({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required PomodoroProvider provider,
  }) {
    final isEn = locale == AppLocale.en;
    final todayMins = provider.todayFocusMinutes;
    final goalMins = provider.dailyFocusGoalMinutes;
    final progress = provider.dailyFocusGoalProgress;
    final pct = (progress * 100).round();
    final ringColor = progress >= 1.0 ? tokens.success : tokens.accent;

    return DesktopPanelCard(
      key: const ValueKey('desktop_focus_daily_goal_ring'),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4.5,
                  backgroundColor: ringColor.withValues(alpha: 0.14),
                  color: ringColor,
                ),
                Text(
                  '$pct%',
                  style: tokens.captionStyle.copyWith(
                    color: tokens.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEn ? 'Daily Focus Goal' : '今日专注目标环',
                  style: tokens.cardTitleStyle.copyWith(fontSize: 13.5),
                ),
                const SizedBox(height: 3),
                Text(
                  isEn
                      ? '$todayMins / $goalMins min completed'
                      : '已完成 $todayMins / $goalMins 分钟',
                  style: tokens.captionStyle.copyWith(
                    color: progress >= 1.0
                        ? tokens.success
                        : tokens.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            key: const ValueKey('desktop_focus_goal_edit_btn'),
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
            onTap: () => _openDailyGoalDialog(provider, locale),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: tokens.mutedSurface,
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                border: Border.all(
                  color: tokens.hairlineBorder,
                  width: DesktopWebTokens.hairlineWidth,
                ),
              ),
              child: Text(
                isEn ? 'Target' : '设定',
                style: tokens.captionStyle.copyWith(color: tokens.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDailyGoalDialog(
    PomodoroProvider provider,
    AppLocale locale,
  ) async {
    final isEn = locale == AppLocale.en;
    var selected = provider.dailyFocusGoalMinutes;
    final ctrl = TextEditingController(text: '$selected');
    try {
      final result = await showDialog<int>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: Text(isEn ? 'Daily Focus Goal' : '设定每日专注目标'),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final mins in const [30, 60, 90, 120, 180, 240])
                        ChoiceChip(
                          label: Text(isEn ? '${mins}m' : '$mins 分钟'),
                          selected: selected == mins,
                          onSelected: (_) => setSt(() {
                            selected = mins;
                            ctrl.text = '$mins';
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: isEn
                          ? 'Target minutes (10-720)'
                          : '目标分钟数 (10-720)',
                    ),
                    onChanged: (raw) {
                      final parsed = int.tryParse(raw.trim());
                      if (parsed != null) {
                        selected = parsed.clamp(10, 720).toInt();
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(isEn ? 'Cancel' : '取消'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = int.tryParse(ctrl.text.trim()) ?? selected;
                  Navigator.of(ctx).pop(parsed.clamp(10, 720).toInt());
                },
                child: Text(isEn ? 'Save' : '保存'),
              ),
            ],
          ),
        ),
      );
      if (result != null && mounted) {
        await provider.setDailyFocusGoalMinutes(result);
      }
    } finally {
      ctrl.dispose();
    }
  }

  Widget _buildTodayStatsCard({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required PomodoroProvider provider,
  }) {
    final isEn = locale == AppLocale.en;
    final todayFocus = provider.todayFocusSessions;
    final todaySeconds = todayFocus.fold<int>(
      0,
      (sum, item) => sum + item.durationSeconds,
    );
    final recent = provider.sessions.take(4).toList(growable: false);

    return DesktopPanelCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, size: 16, color: tokens.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isEn ? 'Today & Recent' : '今日专注统计 & 最近记录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.cardTitleStyle.copyWith(fontSize: 14),
                ),
              ),
              InkWell(
                onTap: () => setState(() => _mode = _FocusStudioMode.history),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    isEn ? 'Details →' : '详情 →',
                    style: tokens.captionStyle.copyWith(color: tokens.accent),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniStatCell(
                  label: isEn ? 'Today' : '今日次数',
                  value: '${provider.sessionCountToday}',
                  tokens: tokens,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MiniStatCell(
                  label: isEn ? 'Today Time' : '今日时长',
                  value: _formatMinutesSummary(todaySeconds ~/ 60, locale),
                  tokens: tokens,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MiniStatCell(
                  label: isEn ? 'Total' : '累计时长',
                  value: _formatMinutesSummary(
                    provider.totalFocusMinutes,
                    locale,
                  ),
                  tokens: tokens,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text(
                  isEn
                      ? 'Start your first focus round today'
                      : '开始第一轮专注，记录就会出现在这里',
                  style: tokens.captionStyle.copyWith(color: tokens.textMuted),
                ),
              ),
            )
          else
            for (final session in recent)
              _CompactSessionRow(
                session: session,
                locale: locale,
                tokens: tokens,
                onEdit: () => showPomodoroSessionEditor(context, session),
                onDelete: () => provider.deleteSession(session.id),
              ),
        ],
      ),
    );
  }

  Widget _buildHistoryView({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required PomodoroProvider provider,
  }) {
    final isEn = locale == AppLocale.en;
    final now = DateTime.now();
    final todaySeconds = provider.todayFocusSessions.fold<int>(
      0,
      (sum, s) => sum + s.durationSeconds,
    );
    final report = FocusReportBuilder.build(
      sessions: provider.sessions,
      penalties: provider.penalties,
      period: _reportPeriod,
      now: now,
    );
    final presentation = FocusReportPresentation.forLocale(
      report,
      locale: locale,
      hasAuthoredUntaggedCollision:
          FocusReportPresentation.detectAuthoredUntaggedCollision(
            report: report,
            sessions: provider.sessions,
          ),
    );
    final markdown = presentation.toMarkdown(
      formatDate: (d) => I18nDateFormat.date(d),
    );

    // Build 7-day chart buckets
    final todayDay = DateTime(now.year, now.month, now.day);
    final dailyMinutes = List<int>.generate(7, (idx) {
      final d = todayDay.subtract(Duration(days: 6 - idx));
      final sec = provider
          .focusSessionsForDate(d)
          .fold<int>(0, (sum, s) => sum + s.durationSeconds);
      return sec ~/ 60;
    });
    final maxBar = math.max(
      30,
      dailyMinutes.fold<int>(0, (m, v) => math.max(m, v)),
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Summary strip + Report controls
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _HistoryMetricTile(
              title: isEn ? 'Today Sessions' : '今日专注次数',
              value: '${provider.sessionCountToday}',
              sub: _formatMinutesSummary(todaySeconds ~/ 60, locale),
              icon: Icons.today_outlined,
              tokens: tokens,
            ),
            _HistoryMetricTile(
              title: _reportPeriod == FocusReportPeriod.week
                  ? (isEn ? 'This Week' : '本周专注')
                  : (isEn ? 'This Month' : '本月专注'),
              value: _formatMinutesSummary(report.totalMinutes, locale),
              sub: isEn
                  ? '${report.sessionCount} sessions · ${report.activeDays} active days'
                  : '${report.sessionCount} 次 · 活跃 ${report.activeDays} 天',
              icon: Icons.date_range_outlined,
              tokens: tokens,
            ),
            _HistoryMetricTile(
              title: isEn ? 'Avg / Longest' : '单次均值 / 最长',
              value: '${report.averageMinutes}m / ${report.longestMinutes}m',
              sub: isEn ? 'Focus rounds' : '有效专注统计',
              icon: Icons.timelapse_rounded,
              tokens: tokens,
            ),
            _HistoryMetricTile(
              title: isEn ? 'Daily Goal' : '今日目标进度',
              value: '${(provider.dailyFocusGoalProgress * 100).round()}%',
              sub:
                  '${provider.todayFocusMinutes} / ${provider.dailyFocusGoalMinutes} min',
              icon: Icons.track_changes_outlined,
              tokens: tokens,
            ),
            _HistoryMetricTile(
              title: isEn ? 'Lifetime Total' : '历史总专注',
              value: _formatMinutesSummary(provider.totalFocusMinutes, locale),
              sub: isEn
                  ? '${provider.sessions.length} total logs'
                  : '累计 ${provider.sessions.length} 条记录',
              icon: Icons.emoji_events_outlined,
              tokens: tokens,
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Markdown report export bar
        DesktopPanelCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 16,
                        color: tokens.accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        presentation.title,
                        style: tokens.cardTitleStyle.copyWith(fontSize: 14),
                      ),
                      const SizedBox(width: 12),
                      SegmentedButton<FocusReportPeriod>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 10),
                          ),
                        ),
                        segments: [
                          ButtonSegment(
                            value: FocusReportPeriod.week,
                            label: Text(isEn ? 'Week' : '本周'),
                          ),
                          ButtonSegment(
                            value: FocusReportPeriod.month,
                            label: Text(isEn ? 'Month' : '本月'),
                          ),
                        ],
                        selected: <FocusReportPeriod>{_reportPeriod},
                        onSelectionChanged: (s) =>
                            setState(() => _reportPeriod = s.first),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => setState(
                          () => _showMarkdownReport = !_showMarkdownReport,
                        ),
                        icon: Icon(
                          _showMarkdownReport
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 16,
                        ),
                        label: Text(isEn ? 'Preview' : '预览报告'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: markdown),
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(
                              content: Text(
                                isEn
                                    ? 'Markdown report copied'
                                    : '已复制 Markdown 专注报告',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 15),
                        label: Text(isEn ? 'Copy Markdown' : '复制报告'),
                      ),
                    ],
                  ),
                ],
              ),
              if (_showMarkdownReport) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tokens.mutedSurface,
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusSm,
                    ),
                  ),
                  child: SelectableText(
                    markdown,
                    style: tokens.bodyMutedStyle.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        LayoutBuilder(
          builder: (context, constraints) {
            final twoCols = constraints.maxWidth >= 860;
            final chartCard = DesktopPanelCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEn ? 'Last 7 Days (Minutes)' : '近 7 日专注趋势（分钟）',
                    style: tokens.cardTitleStyle.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 210,
                    child: BarChart(
                      BarChartData(
                        maxY: maxBar.toDouble() * 1.15,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: tokens.hairlineBorder,
                            strokeWidth: 0.6,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 34,
                              getTitlesWidget: (v, _) => Text(
                                '${v.toInt()}',
                                style: tokens.captionStyle.copyWith(
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) {
                                final d = todayDay.subtract(
                                  Duration(days: 6 - v.toInt()),
                                );
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    '${d.month}/${d.day}',
                                    style: tokens.captionStyle.copyWith(
                                      fontSize: 10.5,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < 7; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: dailyMinutes[i].toDouble(),
                                  color: i == 6
                                      ? tokens.accent
                                      : tokens.accent.withValues(alpha: 0.52),
                                  width: 20,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (report.topTags.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      isEn ? 'TOP FOCUS TAGS' : '标签分布',
                      style: tokens.sectionHeaderStyle,
                    ),
                    const SizedBox(height: 8),
                    for (final tag in report.topTags.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '#${tag.tag}',
                                style: tokens.bodyMutedStyle,
                              ),
                            ),
                            Text(
                              '${tag.totalMinutes}m (${(tag.share * 100).round()}%)',
                              style: tokens.captionStyle,
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            );

            final logCard = DesktopPanelCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEn ? 'All Focus Records' : '专注记录列表',
                    style: tokens.cardTitleStyle.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  if (provider.sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          isEn ? 'No focus sessions yet' : '暂无专注记录',
                          style: tokens.bodyMutedStyle,
                        ),
                      ),
                    )
                  else
                    for (final session in provider.sessions.take(50))
                      _CompactSessionRow(
                        session: session,
                        locale: locale,
                        tokens: tokens,
                        showDate: true,
                        onEdit: () =>
                            showPomodoroSessionEditor(context, session),
                        onDelete: () => provider.deleteSession(session.id),
                      ),
                ],
              ),
            );

            if (!twoCols) {
              return Column(
                children: [chartCard, const SizedBox(height: 12), logCard],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: chartCard),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: logCard),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildStudyRoomsView({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required PomodoroProvider provider,
    required FocusRoomProvider? roomsProvider,
    required AuthProvider? auth,
  }) {
    final isEn = locale == AppLocale.en;
    if (roomsProvider == null) {
      return Center(
        child: Text(
          isEn ? 'Study rooms unavailable' : '自习室服务暂未加载',
          style: tokens.bodyMutedStyle,
        ),
      );
    }

    final activeRoom = roomsProvider.activeRoom;
    final authName = auth?.state.displayName?.trim().isNotEmpty == true
        ? auth!.state.displayName!.trim()
        : auth?.state.username?.trim();
    final displayName = (authName != null && authName.isNotEmpty)
        ? authName
        : FocusRoomUiCopy.selfDisplayNameFallback(locale);

    return LayoutBuilder(
      builder: (context, constraints) {
        final roomListPanel = DesktopPanelCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    FocusRoomUiCopy.studyRoomTitle(locale),
                    style: tokens.cardTitleStyle.copyWith(fontSize: 15),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: isEn ? 'Join by invite code' : '输入邀请码加入',
                    icon: const Icon(Icons.qr_code_rounded, size: 17),
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        _showInviteCodeDialog(context, roomsProvider, locale),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        _showCreateRoomDialog(context, roomsProvider, locale),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 28),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: Text(
                      isEn ? 'Create' : '新建',
                      style: tokens.captionStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final room in roomsProvider.rooms) ...[
                _StudyRoomCardTile(
                  room: room,
                  isJoined: roomsProvider.joinedRoomIds.contains(room.id),
                  isActive: roomsProvider.activeRoomId == room.id,
                  locale: locale,
                  tokens: tokens,
                  onTap: () {
                    if (roomsProvider.joinedRoomIds.contains(room.id)) {
                      roomsProvider.setActiveRoom(room.id);
                    } else {
                      roomsProvider.joinRoom(room.id);
                    }
                    provider.setFocusRoomId(room.id);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );

        final rankingPanel = _buildStudyRoomLeaderboardCard(
          tokens: tokens,
          locale: locale,
          provider: provider,
          roomsProvider: roomsProvider,
          activeRoom: activeRoom,
          displayName: displayName,
        );

        if (constraints.maxWidth < 880) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              roomListPanel,
              const SizedBox(height: 14),
              rankingPanel,
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 340,
                child: SingleChildScrollView(child: roomListPanel),
              ),
              const SizedBox(width: 16),
              Expanded(child: SingleChildScrollView(child: rankingPanel)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudyRoomLeaderboardCard({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required PomodoroProvider provider,
    required FocusRoomProvider roomsProvider,
    required FocusRoom? activeRoom,
    required String displayName,
  }) {
    final isEn = locale == AppLocale.en;
    final room = activeRoom ??
        (roomsProvider.rooms.isEmpty ? null : roomsProvider.rooms.first);
    final List<FocusRoomRankingEntry> entries;
    final String heading;
    final int? weeklyTargetSeconds;
    final int? userWeeklySeconds;

    if (_roomLeaderboardSegment == 0 && room != null) {
      final r = roomsProvider.effectiveRankingFor(
        room.id,
        provider.sessions,
        currentUserName: displayName,
      );
      entries = r.entries;
      heading = room.nameFor(locale);
      weeklyTargetSeconds = room.weeklyTargetSeconds;
      userWeeklySeconds = r.userWeeklySeconds;
    } else if (_roomLeaderboardSegment == 1) {
      final s = roomsProvider.socialRankingFor(
        FocusLeaderboardScope.friends,
        provider.sessions,
        currentUserName: displayName,
      );
      entries = s.entries;
      heading = isEn ? 'Friends Ranking' : '专注好友榜';
      weeklyTargetSeconds = null;
      userWeeklySeconds = null;
    } else {
      final s = roomsProvider.socialRankingFor(
        FocusLeaderboardScope.global,
        provider.sessions,
        currentUserName: displayName,
      );
      entries = s.entries;
      heading = isEn ? 'Global Ranking' : '全站专注榜';
      weeklyTargetSeconds = null;
      userWeeklySeconds = null;
    }

    return DesktopPanelCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.pageTitleStyle.copyWith(fontSize: 16),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text(isEn ? 'Room' : '本室'),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text(isEn ? 'Friends' : '好友'),
                  ),
                  ButtonSegment(
                    value: 2,
                    label: Text(isEn ? 'Global' : '全站'),
                  ),
                ],
                selected: <int>{_roomLeaderboardSegment},
                onSelectionChanged: (sel) =>
                    setState(() => _roomLeaderboardSegment = sel.first),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: isEn ? 'Refresh rankings' : '刷新排行',
                icon: const Icon(Icons.refresh_rounded, size: 17),
                onPressed: () {
                  if (_roomLeaderboardSegment == 0) {
                    roomsProvider.syncRemoteRankings(
                      provider.sessions,
                      displayName: displayName,
                      force: true,
                    );
                  } else if (_roomLeaderboardSegment == 1) {
                    roomsProvider.loadFocusFriendsAndRanking(force: true);
                  } else {
                    roomsProvider.loadGlobalRanking(force: true);
                  }
                },
              ),
            ],
          ),
          if (weeklyTargetSeconds != null &&
              weeklyTargetSeconds > 0 &&
              userWeeklySeconds != null) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final ratio = (userWeeklySeconds! / weeklyTargetSeconds!)
                    .clamp(0.0, 1.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isEn
                              ? 'Your weekly target progress'
                              : '本周自习目标进度',
                          style: tokens.captionStyle,
                        ),
                        const Spacer(),
                        Text(
                          '${_formatMinutesSummary(userWeeklySeconds ~/ 60, locale)} / ${_formatMinutesSummary(weeklyTargetSeconds ~/ 60, locale)}',
                          style: tokens.captionStyle.copyWith(
                            color: tokens.accent,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        DesktopWebTokens.radiusPill,
                      ),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: tokens.mutedSurface,
                        color: tokens.accent,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 14),
          for (final entry in entries)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: entry.isCurrentUser
                    ? tokens.accentSoft
                    : tokens.mutedSurface,
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                border: Border.all(
                  color: entry.isCurrentUser
                      ? tokens.accentBorder
                      : tokens.hairlineBorder,
                  width: DesktopWebTokens.hairlineWidth,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '#${entry.rank}',
                      style: tokens.bodyStyle.copyWith(
                        fontSize: 13,
                        color: entry.rank <= 3
                            ? tokens.accent
                            : tokens.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: entry.online ? tokens.success : tokens.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.bodyStyle.copyWith(fontSize: 13.5),
                    ),
                  ),
                  Text(
                    isEn
                        ? '${entry.sessionCount} rounds'
                        : '${entry.sessionCount} 次',
                    style: tokens.captionStyle.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    _formatMinutesSummary(entry.weeklySeconds ~/ 60, locale),
                    style: tokens.bodyStyle.copyWith(
                      fontSize: 13.5,
                      color: entry.isCurrentUser
                          ? tokens.accent
                          : tokens.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showCreateRoomDialog(
    BuildContext context,
    FocusRoomProvider roomsProvider,
    AppLocale locale,
  ) async {
    final isEn = locale == AppLocale.en;
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final goalCtrl = TextEditingController(text: '300');
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(FocusRoomUiCopy.createRoomTitle(locale)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: FocusRoomUiCopy.nameLabel(locale),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: FocusRoomUiCopy.descriptionLabel(locale),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: goalCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: FocusRoomUiCopy.weeklyGoalMinutesLabel(locale),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(FocusRoomUiCopy.cancel(locale)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(FocusRoomUiCopy.create(locale)),
          ),
        ],
      ),
    );
    if (created == true) {
      final mins = int.tryParse(goalCtrl.text.trim()) ?? 300;
      await roomsProvider.createRoom(
        name: nameCtrl.text.trim().isEmpty
            ? (isEn ? 'My Study Room' : '我的自习室')
            : nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
        weeklyTargetMinutes: mins.clamp(30, 10080),
      );
    }
    nameCtrl.dispose();
    descCtrl.dispose();
    goalCtrl.dispose();
  }

  Future<void> _showInviteCodeDialog(
    BuildContext context,
    FocusRoomProvider roomsProvider,
    AppLocale locale,
  ) async {
    final isEn = locale == AppLocale.en;
    final codeCtrl = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(FocusRoomUiCopy.enterInviteCodeAction(locale)),
        content: SizedBox(
          width: 340,
          child: TextField(
            controller: codeCtrl,
            decoration: InputDecoration(
              labelText: isEn ? 'Invite code' : '输入自习室邀请码',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(FocusRoomUiCopy.cancel(locale)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(FocusRoomUiCopy.ok(locale)),
          ),
        ],
      ),
    );
    if (submit == true && codeCtrl.text.trim().isNotEmpty) {
      try {
        await roomsProvider.acceptInviteCode(codeCtrl.text.trim());
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
    codeCtrl.dispose();
  }
}

class _FocusModeTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _FocusModeTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? tokens.elevatedSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
          boxShadow: selected ? tokens.cardShadow : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? tokens.accent : tokens.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: tokens.captionStyle.copyWith(
                fontSize: 12.5,
                color: selected ? tokens.accent : tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopTimerRing extends StatelessWidget {
  final double size;
  final double progress;
  final String timeText;
  final String subtitleText;
  final Color accentColor;
  final bool isRunning;
  final bool isCountUp;
  final Animation<double> haloAnimation;
  final DesktopWebTokens tokens;

  const _DesktopTimerRing({
    required this.size,
    required this.progress,
    required this.timeText,
    required this.subtitleText,
    required this.accentColor,
    required this.isRunning,
    required this.isCountUp,
    required this.haloAnimation,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final dialDisc = RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tokens.panelSurface,
          border: Border.all(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
          boxShadow: tokens.cardShadow,
        ),
        child: CustomPaint(
          painter: _TimerRingPainter(
            progress: progress,
            color: accentColor,
            trackColor: tokens.textPrimary.withValues(
              alpha: tokens.isDark ? 0.11 : 0.085,
            ),
            isCountUp: isCountUp,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeText,
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 1.0,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitleText,
                  style: tokens.captionStyle.copyWith(
                    fontSize: 12.5,
                    letterSpacing: 0.6,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      width: size + 56,
      height: size + 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Breathing ambient halo isolated inside RepaintBoundary
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: haloAnimation,
              builder: (context, _) {
                final pulse = isRunning
                    ? (0.5 + 0.5 * math.sin(haloAnimation.value * math.pi))
                    : 0.0;
                final haloRadius = size + 38 + pulse * 16;
                return Container(
                  width: haloRadius,
                  height: haloRadius,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accentColor.withValues(
                          alpha: (isRunning ? 0.14 + pulse * 0.08 : 0.07),
                        ),
                        accentColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          dialDisc,
        ],
      ),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  final bool isCountUp;

  const _TimerRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.isCountUp,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 12;
    const strokeWidth = 7.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweep = isCountUp
        ? math.pi * 0.55
        : (2 * math.pi * progress.clamp(0.0, 1.0));
    final startAngle = isCountUp
        ? (-math.pi / 2 + 2 * math.pi * progress)
        : -math.pi / 2;

    if (sweep > 0.005) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimerRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.isCountUp != isCountUp;
}

class _PresetDurationChip extends StatelessWidget {
  final String label;
  final bool selected;
  final DesktopWebTokens tokens;
  final Color accentColor;
  final bool enabled;
  final VoidCallback onTap;

  const _PresetDurationChip({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.accentColor,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabledAlpha = enabled ? 1.0 : 0.55;
    final bgColor = selected
        ? accentColor.withValues(
            alpha: (tokens.isDark ? 0.20 : 0.12) * disabledAlpha,
          )
        : tokens.panelSurface.withValues(
            alpha: tokens.panelSurface.a * disabledAlpha,
          );
    final borderColor = selected
        ? accentColor.withValues(alpha: 0.50 * disabledAlpha)
        : tokens.hairlineBorder.withValues(
            alpha: tokens.hairlineBorder.a * disabledAlpha,
          );
    final textColor = (selected ? accentColor : tokens.textSecondary)
        .withValues(
          alpha:
              (selected ? accentColor : tokens.textSecondary).a * disabledAlpha,
        );
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
          border: Border.all(
            color: borderColor,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
        child: Text(
          label,
          style: tokens.captionStyle.copyWith(
            fontSize: 12,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class _MiniStatCell extends StatelessWidget {
  final String label;
  final String value;
  final DesktopWebTokens tokens;

  const _MiniStatCell({
    required this.label,
    required this.value,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.mutedSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.captionStyle.copyWith(fontSize: 10.5),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.cardTitleStyle.copyWith(
              fontSize: 14,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSessionRow extends StatelessWidget {
  final PomodoroSession session;
  final AppLocale locale;
  final DesktopWebTokens tokens;
  final bool showDate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CompactSessionRow({
    required this.session,
    required this.locale,
    required this.tokens,
    this.showDate = false,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = locale == AppLocale.en;
    final isFocus = session.type == PomodoroType.focus;
    final mins = session.durationSeconds ~/ 60;
    final dotColor = isFocus ? tokens.accent : tokens.success;
    final title = session.taskName?.trim().isNotEmpty == true
        ? session.taskName!
        : (isFocus
              ? (isEn ? '$mins min Focus' : '$mins 分钟专注')
              : (isEn ? '$mins min Break' : '$mins 分钟休息'));
    final when = showDate
        ? '${I18nDateFormat.monthDay(session.startTime)} ${I18nDateFormat.time(session.startTime)}'
        : I18nDateFormat.time(session.startTime);

    return DesktopHoverTile(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      onTap: onEdit,
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.bodyStyle.copyWith(fontSize: 12.5),
                ),
                Text(
                  '$when · ${mins}m',
                  style: tokens.captionStyle.copyWith(
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isEn ? 'Edit' : '编辑',
            icon: Icon(Icons.edit_outlined, size: 14, color: tokens.textMuted),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: isEn ? 'Delete' : '删除',
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 14,
              color: tokens.textMuted,
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _HistoryMetricTile extends StatelessWidget {
  final String title;
  final String value;
  final String sub;
  final IconData icon;
  final DesktopWebTokens tokens;

  const _HistoryMetricTile({
    required this.title,
    required this.value,
    required this.sub,
    required this.icon,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: DesktopPanelCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
              ),
              child: Icon(icon, size: 18, color: tokens.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tokens.captionStyle),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.metricValueStyle.copyWith(
                      fontSize: 18,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.captionStyle.copyWith(
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudyRoomCardTile extends StatelessWidget {
  final FocusRoom room;
  final bool isJoined;
  final bool isActive;
  final AppLocale locale;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _StudyRoomCardTile({
    required this.room,
    required this.isJoined,
    required this.isActive,
    required this.locale,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = locale == AppLocale.en;
    final roomColor = Color(room.accentColor);
    return DesktopHoverTile(
      selected: isActive,
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: roomColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
            ),
            child: Icon(Icons.menu_book_rounded, size: 17, color: roomColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.nameFor(locale),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.bodyStyle.copyWith(
                    fontSize: 13.5,
                    color: isActive ? tokens.accent : tokens.textPrimary,
                  ),
                ),
                Text(
                  room.descriptionFor(locale),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.captionStyle.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isActive
                  ? tokens.accentSoft
                  : (isJoined ? tokens.mutedSurface : tokens.selectedSurface),
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
            ),
            child: Text(
              isActive
                  ? (isEn ? 'Active' : '当前')
                  : (isJoined
                        ? (isEn ? 'Joined' : '已加入')
                        : (isEn ? 'Join' : '加入')),
              style: tokens.captionStyle.copyWith(
                fontSize: 10.5,
                color: isActive ? tokens.accent : tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusTagPill extends StatefulWidget {
  final String label;
  final bool selected;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _FocusTagPill({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  @override
  State<_FocusTagPill> createState() => _FocusTagPillState();
}

class _FocusTagPillState extends State<_FocusTagPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected
                ? tokens.accentSoft
                : (_hovered ? tokens.hoverSurface : tokens.mutedSurface),
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
            border: Border.all(
              color: selected
                  ? tokens.accentBorder
                  : (_hovered ? tokens.strongBorder : tokens.hairlineBorder),
              width: DesktopWebTokens.hairlineWidth,
            ),
          ),
          child: Text(
            widget.label,
            style: tokens.captionStyle.copyWith(
              fontSize: 11,
              color: selected
                  ? tokens.accent
                  : (_hovered ? tokens.textPrimary : tokens.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
