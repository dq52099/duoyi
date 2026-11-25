import '../core/i18n.dart';
import '../models/pomodoro.dart';
import '../providers/pomodoro_provider.dart';

/// Changes that require a fresh widget payload. Active timer ticks keep a
/// stable signature because native widgets count from the published anchor.
String pomodoroWidgetChangeSignature(PomodoroProvider provider) {
  final state = provider.state;
  final remaining = state.isRunning ? 'active' : state.remainingSeconds;
  return '${provider.persistedRevision}:${provider.sessionCountToday}:'
      '${state.isRunning}:${state.isCountUp}:${state.type.index}:'
      '${state.totalSeconds}:$remaining:${provider.effectiveFocusDuration}';
}

/// The next focus session follows the effective configuration; changing a
/// preference must not change an already running or paused phase.
String nextFocusWidgetLabel(
  PomodoroProvider provider, {
  required AppLocale locale,
}) =>
    '${provider.effectiveFocusDuration ~/ 60}'
    '${I18n.trForLocale('widget.next_focus_suffix', locale)}';

/// Elapsed completion ratio in `[0.0, 1.0]` for widget progress bars.
double widgetFocusProgressRatio(PomodoroState state) {
  if (state.isCountUp) {
    return state.remainingSeconds > 0 ? 1.0 : 0.0;
  }
  if (state.totalSeconds <= 0) return 0.0;
  final elapsed = (state.totalSeconds - state.remainingSeconds).clamp(
    0,
    state.totalSeconds,
  );
  return (elapsed / state.totalSeconds).clamp(0.0, 1.0).toDouble();
}

/// Localized status pill label reflecting running, paused, break, or idle state.
String widgetFocusStateLabel(
  PomodoroState state, {
  required AppLocale locale,
}) {
  if (state.isRunning) {
    if (state.type == PomodoroType.shortBreak ||
        state.type == PomodoroType.longBreak) {
      return switch (locale) {
        AppLocale.zh => '休息中',
        AppLocale.en => 'On Break',
      };
    }
    return switch (locale) {
      AppLocale.zh => '专注中',
      AppLocale.en => 'Focusing',
    };
  }
  final hasProgress = !state.isCountUp
      ? state.remainingSeconds < state.totalSeconds && state.remainingSeconds > 0
      : state.remainingSeconds > 0;
  if (hasProgress) {
    return switch (locale) {
      AppLocale.zh => '已暂停',
      AppLocale.en => 'Paused',
    };
  }
  return switch (locale) {
    AppLocale.zh => '待开始',
    AppLocale.en => 'Ready',
  };
}
