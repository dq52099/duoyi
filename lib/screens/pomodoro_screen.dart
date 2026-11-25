import '../widgets/app_date_format.dart';
import '../core/i18n_date_format.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/brand_strings.dart';
import '../core/design_tokens.dart';
import '../core/desktop_tokens.dart';
import '../core/focus_report.dart';
import '../core/focus_report_presentation.dart';
import '../core/focus_room_ui_copy.dart';
import '../core/focus_sound_catalog.dart';
import '../core/i18n.dart';
import '../core/main_ui_copy.dart';
import '../models/focus_room.dart';
import '../models/pomodoro.dart';
import '../models/todo.dart';
import '../providers/custom_focus_sound_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/focus_room_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/todo_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/settings_action_origin.dart';
import '../services/api_client.dart';
import '../services/focus_room_api.dart';
import '../services/focus_sound_service.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/brand_background.dart';
import '../widgets/pomodoro_timer_ring.dart';
import '../widgets/pomodoro_session_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/controller_dialog.dart' show showControllerDialog;
import '../widgets/surface_components.dart';

String _focusRoomErrorText(Object error) {
  final message = error is ApiException ? error.message : error.toString();
  if (isFocusRoomRealtimeTransportError(error)) {
    return focusRoomRankingUnavailableMessage;
  }
  if (isBackendCompatibilityDiagnosticMessage(message)) return message;
  return userVisibleApiError(
    error,
    fallbackMessage: FocusRoomUiCopy.serviceUnavailableFallback(I18n.current),
  );
}

Future<void> showPomodoroSessionEditor(
  BuildContext context,
  PomodoroSession session,
) async {
  final provider = context.read<PomodoroProvider>();
  final editorGeneration = AccountLocalDataCleaner.accountDataGeneration;
  final rooms =
      context.read<FocusRoomProvider?>()?.rooms ?? const <FocusRoom>[];
  final customProvider = context.read<CustomFocusSoundProvider?>();
  final customSounds = customProvider?.sounds ?? const <CustomFocusSound>[];
  final taskCtrl = TextEditingController(text: session.taskName ?? '');
  final tagCtrl = TextEditingController(text: session.tag ?? '');
  final durationCtrl = TextEditingController(
    text: (session.durationSeconds ~/ 60).clamp(1, 24 * 60).toString(),
  );
  var date = DateTime(
    session.startTime.year,
    session.startTime.month,
    session.startTime.day,
  );
  var startTime = TimeOfDay.fromDateTime(session.startTime);
  var selectedType = session.type;
  var selectedSound = session.whiteNoiseSound.trim().isEmpty
      ? FocusSoundCatalog.none
      : session.whiteNoiseSound;
  var selectedRoomId = rooms.any((room) => room.id == session.focusRoomId)
      ? session.focusRoomId
      : null;
  var saveInFlight = false;
  TransitionRoute<dynamic>? editorRoute;

  bool isCurrentEditorSession() =>
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(editorGeneration);

  DateTime combineStart() => DateTime(
    date.year,
    date.month,
    date.day,
    startTime.hour,
    startTime.minute,
  );

  try {
    await showAppModalSheet<void>(
      context: context,
      builder: (sheetCtx) {
        editorRoute ??= ModalRoute.of(sheetCtx);
        return ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (sheetCtx, locale, _) => StatefulBuilder(
            builder: (sheetCtx, setSt) {
              Future<void> previewSound(String value) async {
                if (!isCurrentEditorSession() || !sheetCtx.mounted) return;
                setSt(() => selectedSound = value);
                if (value == FocusSoundCatalog.none) {
                  await FocusSoundService.instance.stop();
                  return;
                }
                if (!isCurrentEditorSession() || !sheetCtx.mounted) return;
                await FocusSoundService.instance.setVolume(
                  provider.config.focusSoundVolume,
                );
                final started = await FocusSoundService.instance.preview(value);
                if (!started &&
                    isCurrentEditorSession() &&
                    context.mounted &&
                    sheetCtx.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(
                      content: Text(
                        FocusRoomUiCopy.soundPreviewFailed(I18n.current),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }

              Future<void> save() async {
                if (saveInFlight || !isCurrentEditorSession()) return;
                saveInFlight = true;
                final messenger = ScaffoldMessenger.maybeOf(context);
                final navigator = Navigator.of(sheetCtx);
                final ownedRoute = ModalRoute.of(sheetCtx);
                try {
                  final minutes = int.tryParse(durationCtrl.text.trim()) ?? 0;
                  if (minutes < 1 || minutes > 24 * 60) {
                    messenger?.showSnackBar(
                      SnackBar(
                        content: Text(
                          FocusRoomUiCopy.durationRangeError(I18n.current),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  final start = combineStart();
                  final next = session.copyWith(
                    startTime: start,
                    endTime: start.add(Duration(minutes: minutes)),
                    durationSeconds: minutes * 60,
                    type: selectedType,
                    taskName: taskCtrl.text.trim().isEmpty
                        ? null
                        : taskCtrl.text.trim(),
                    clearTaskName: taskCtrl.text.trim().isEmpty,
                    tag: tagCtrl.text.trim().isEmpty
                        ? null
                        : tagCtrl.text.trim(),
                    clearTag: tagCtrl.text.trim().isEmpty,
                    whiteNoiseSound: selectedSound,
                    focusRoomId: selectedRoomId,
                    clearFocusRoomId: selectedRoomId == null,
                  );
                  if (!isCurrentEditorSession()) return;
                  final ok = await provider.updateSession(next);
                  if (!isCurrentEditorSession()) return;
                  if (!ok) {
                    messenger?.showSnackBar(
                      SnackBar(
                        content: Text(
                          FocusRoomUiCopy.sessionDeletedError(I18n.current),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  if (!context.mounted || ownedRoute == null) return;
                  final covered = !ownedRoute.isCurrent;
                  if (ownedRoute.isActive) {
                    navigator.removeRoute(ownedRoute);
                  }
                  if (covered) return;
                  messenger?.showSnackBar(
                    SnackBar(
                      content: Text(
                        FocusRoomUiCopy.sessionSavedSuccess(I18n.current),
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(milliseconds: 1200),
                    ),
                  );
                } finally {
                  saveInFlight = false;
                }
              }

              return AppModalSheet(
                title: FocusRoomUiCopy.editSessionTitle(locale),
                subtitle: FocusRoomUiCopy.editSessionSubtitle(locale),
                shiftForKeyboard: true,
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                    child: Text(FocusRoomUiCopy.cancel(locale)),
                  ),
                  FilledButton(
                    onPressed: save,
                    child: Text(FocusRoomUiCopy.save(locale)),
                  ),
                ],
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: taskCtrl,
                      decoration: InputDecoration(
                        labelText: FocusRoomUiCopy.taskNameLabel(locale),
                        prefixIcon: const Icon(Icons.task_alt_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: tagCtrl,
                      decoration: InputDecoration(
                        labelText: FocusRoomUiCopy.taskTagLabel(locale),
                        prefixIcon: const Icon(Icons.sell_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.calendar_today_outlined),
                            title: Text(FocusRoomUiCopy.dateLabel(locale)),
                            subtitle: Text(AppDateFormat.date(sheetCtx, date)),
                            onTap: () async {
                              final pickerGeneration =
                                  AccountLocalDataCleaner.accountDataGeneration;
                              final picked = await AppDatePicker.pickSolar(
                                sheetCtx,
                                initialDate: date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2099, 12, 31),
                                titleKey: 'picker.date.title',
                              );
                              if (picked == null ||
                                  !isCurrentEditorSession() ||
                                  pickerGeneration !=
                                      AccountLocalDataCleaner
                                          .accountDataGeneration ||
                                  !sheetCtx.mounted) {
                                return;
                              }
                              setSt(() {
                                date = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                );
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.schedule_outlined),
                            title: Text(FocusRoomUiCopy.startTimeLabel(locale)),
                            subtitle: Text(AppTimePicker.format(startTime)),
                            onTap: () async {
                              final pickerGeneration =
                                  AccountLocalDataCleaner.accountDataGeneration;
                              final picked = await AppTimePicker.show(
                                sheetCtx,
                                initialTime: startTime,
                                titleKey: 'picker.time.title',
                                minuteStep: 5,
                              );
                              if (picked == null ||
                                  !isCurrentEditorSession() ||
                                  pickerGeneration !=
                                      AccountLocalDataCleaner
                                          .accountDataGeneration ||
                                  !sheetCtx.mounted) {
                                return;
                              }
                              setSt(() => startTime = picked);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: durationCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: FocusRoomUiCopy.durationMinutesLabel(locale),
                        prefixIcon: const Icon(Icons.hourglass_bottom_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<PomodoroType>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: PomodoroType.focus,
                          label: Text(FocusRoomUiCopy.focusTypeFocus(locale)),
                          icon: const Icon(Icons.timer_outlined),
                        ),
                        ButtonSegment(
                          value: PomodoroType.shortBreak,
                          label: Text(
                            FocusRoomUiCopy.focusTypeShortBreak(locale),
                          ),
                          icon: const Icon(Icons.free_breakfast_outlined),
                        ),
                        ButtonSegment(
                          value: PomodoroType.longBreak,
                          label: Text(
                            FocusRoomUiCopy.focusTypeLongBreak(locale),
                          ),
                          icon: const Icon(Icons.weekend_outlined),
                        ),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (value) =>
                          setSt(() => selectedType = value.first),
                    ),
                    const SizedBox(height: 12),
                    AppDropdownField<String>(
                      key: const ValueKey('focus-session-sound'),
                      initialValue: selectedSound,
                      decoration: InputDecoration(
                        labelText: FocusRoomUiCopy.whiteNoiseLabel(locale),
                        prefixIcon: const Icon(Icons.music_note_outlined),
                      ),
                      items: [
                        for (final option in FocusSoundCatalog.options)
                          DropdownMenuItem(
                            value: option.id,
                            child: Text(option.displayLabel(locale: locale)),
                          ),
                        for (final sound in customSounds)
                          DropdownMenuItem(
                            value: sound.id,
                            child: Text(sound.label),
                          ),
                        if (selectedSound != FocusSoundCatalog.none &&
                            !FocusSoundCatalog.options.any(
                              (option) => option.id == selectedSound,
                            ) &&
                            !customSounds.any(
                              (sound) => sound.id == selectedSound,
                            ))
                          DropdownMenuItem(
                            value: selectedSound,
                            child: Text(
                              selectedSound.startsWith(
                                    CustomFocusSoundProvider.idPrefix,
                                  )
                                  ? (customProvider?.labelFor(selectedSound) ??
                                        FocusRoomUiCopy.customAudioLabel(
                                          locale,
                                        ))
                                  : selectedSound,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          previewSound(value ?? FocusSoundCatalog.none),
                    ),
                    const SizedBox(height: 10),
                    AppDropdownField<String>(
                      key: const ValueKey('focus-session-room'),
                      initialValue: selectedRoomId ?? '',
                      decoration: InputDecoration(
                        labelText: FocusRoomUiCopy.studyRoomLabel(locale),
                        prefixIcon: const Icon(Icons.meeting_room_outlined),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(FocusRoomUiCopy.noAssociatedRoom(locale)),
                        ),
                        for (final room in rooms)
                          DropdownMenuItem(
                            value: room.id,
                            child: Text(room.nameFor(locale)),
                          ),
                      ],
                      onChanged: (value) => setSt(
                        () => selectedRoomId = value == null || value.isEmpty
                            ? null
                            : value,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  } finally {
    // A modal route may still be tearing down after its result future
    // completes. Wait for that transition and one frame before disposing the
    // controllers used by the sheet's text fields.
    if (editorRoute != null) {
      await editorRoute!.completed;
    }
    await WidgetsBinding.instance.endOfFrame;
    taskCtrl.dispose();
    tagCtrl.dispose();
    durationCtrl.dispose();
  }
}

class PomodoroScreen extends StatelessWidget
    implements LocaleStatePreservingRoute {
  final bool useShellBackground;

  const PomodoroScreen({super.key, this.useShellBackground = false});

  @override
  Widget build(BuildContext context) {
    if (context.read<PomodoroProvider?>() == null ||
        context.read<FocusRoomProvider?>() == null ||
        context.read<ThemeProvider?>() == null ||
        context.read<CustomFocusSoundProvider?>() == null ||
        context.read<AuthProvider?>() == null) {
      return _PomodoroProviderFallback(
        child: _PomodoroScreenBody(useShellBackground: useShellBackground),
      );
    }
    return _PomodoroScreenBody(useShellBackground: useShellBackground);
  }
}

class _PomodoroScreenBody extends StatefulWidget {
  final bool useShellBackground;

  const _PomodoroScreenBody({this.useShellBackground = false});

  @override
  State<_PomodoroScreenBody> createState() => _PomodoroScreenState();
}

class _PomodoroProviderFallback extends StatefulWidget {
  final Widget child;

  const _PomodoroProviderFallback({required this.child});

  @override
  State<_PomodoroProviderFallback> createState() =>
      _PomodoroProviderFallbackState();
}

class _PomodoroProviderFallbackState extends State<_PomodoroProviderFallback> {
  late final PomodoroProvider _pomodoro = PomodoroProvider();
  late final ThemeProvider _theme = ThemeProvider();
  late final FocusRoomProvider _rooms = FocusRoomProvider();
  late final CustomFocusSoundProvider _customSounds =
      CustomFocusSoundProvider();
  late final AuthProvider _auth = AuthProvider();

  @override
  void initState() {
    super.initState();
    _pomodoro.attachLifecycle();
    unawaited(_pomodoro.loadFromStorage());
    unawaited(_rooms.loadFromStorage());
    unawaited(_customSounds.loadFromStorage());
  }

  @override
  void dispose() {
    _pomodoro.dispose();
    _theme.dispose();
    _rooms.dispose();
    _customSounds.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PomodoroProvider>.value(value: _pomodoro),
        ChangeNotifierProvider<ThemeProvider>.value(value: _theme),
        ChangeNotifierProvider<FocusRoomProvider>.value(value: _rooms),
        ChangeNotifierProvider<CustomFocusSoundProvider>.value(
          value: _customSounds,
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
      ],
      child: widget.child,
    );
  }
}

class _PomodoroDialogBody extends StatelessWidget {
  final Widget child;

  const _PomodoroDialogBody({required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = (media.size.height - media.viewInsets.bottom - 180)
        .clamp(220.0, 520.0)
        .toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
      child: AppSecondaryControlTheme(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: child,
        ),
      ),
    );
  }
}

class _PomodoroScreenState extends State<_PomodoroScreenBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  Future<void> _selectDuration(
    BuildContext actionContext,
    PomodoroProvider provider,
    SettingsActionOrigin origin,
    int providerGeneration, {
    int? minutes,
  }) async {
    bool isCurrent() =>
        mounted &&
        actionContext.mounted &&
        origin.isCurrent() &&
        identical(actionContext.read<PomodoroProvider?>(), provider) &&
        provider.storageGeneration == providerGeneration;
    if (!isCurrent() || provider.state.isRunning) return;
    final messenger = ScaffoldMessenger.maybeOf(actionContext);
    try {
      if (minutes == null) {
        await provider.useDefaultFocusDuration();
      } else {
        await provider.setFocusDuration(minutes * 60);
      }
    } catch (_) {
      if (!isCurrent()) return;
      if (messenger?.mounted != true) return;
      messenger!.showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (_, locale, _) =>
                Text(FocusRoomUiCopy.durationSaveFailed(locale)),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    I18n.localeListenable.addListener(_onLocaleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pomodoro = context.read<PomodoroProvider>();
      final rooms = context.read<FocusRoomProvider>();
      pomodoro.refreshFocusDndStatus();
      if (pomodoro.state.focusRoomId == null && rooms.activeRoomId != null) {
        unawaited(pomodoro.setFocusRoomId(rooms.activeRoomId));
      }
    });
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _typeColor(PomodoroType t, ColorScheme cs) {
    switch (t) {
      case PomodoroType.focus:
        return DesignTokens.defaultError;
      case PomodoroType.shortBreak:
        return DesignTokens.defaultSuccess;
      case PomodoroType.longBreak:
        return cs.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.select<ThemeProvider, BrandStrings>(
      (t) => t.brand.strings,
    );

    String typeLabel(PomodoroType t) {
      switch (t) {
        case PomodoroType.focus:
          return MainUiCopy.pomodoroCountdownMode;
        case PomodoroType.shortBreak:
          return s.focusStateShortBreak;
        case PomodoroType.longBreak:
          return s.focusStateLongBreak;
      }
    }

    return _MaybePomodoroBackground(
      enabled: !widget.useShellBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(s.focusTitle),
          bottom: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: s.focusTabTimer),
              Tab(text: s.focusTabHistory),
              Tab(
                text: FocusRoomUiCopy.roomTab(I18n.current),
              ), // const Tab(text: '自习室')
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            Selector<PomodoroProvider, _TimerTabSlice>(
              selector: (_, provider) {
                final st = provider.state;
                final notStarted = st.isCountUp
                    ? st.remainingSeconds == 0
                    : st.remainingSeconds == st.totalSeconds;
                return _TimerTabSlice(
                  storageGeneration: provider.storageGeneration,
                  type: st.type,
                  isCountUp: st.isCountUp,
                  isRunning: st.isRunning,
                  isNotStarted: notStarted,
                  totalSeconds: st.totalSeconds,
                  completedSessions: st.completedSessions,
                  taskName: st.taskName,
                  whiteNoiseSound: st.whiteNoiseSound,
                  focusRoomId: st.focusRoomId,
                  defaultFocusMinutes: provider.defaultFocusMinutes,
                  focusDurationUsesDefault:
                      provider.config.focusDurationUsesDefault,
                );
              },
              builder: (context, slice, _) {
                final provider = context.read<PomodoroProvider>();
                final durationOrigin = SettingsActionOrigin(context);
                final durationGeneration = slice.storageGeneration;
                final s = context.select<ThemeProvider, BrandStrings>(
                  (t) => t.brand.strings,
                );
                final focusBackdrop =
                    context.select<ThemeProvider, FocusBackdropReward>(
                      (t) => t.activeFocusBackdrop,
                    );
                final color = _typeColor(
                  slice.type,
                  Theme.of(context).colorScheme,
                );
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final availableHeight = constraints.maxHeight;
                    final compact = availableHeight < 660;
                    final tight = availableHeight < 560;
                    final ringSize = tight
                        ? 126.0
                        : compact
                        ? 148.0
                        : 172.0;
                    final cardPadding = tight
                        ? const EdgeInsets.all(10)
                        : compact
                        ? const EdgeInsets.all(12)
                        : const EdgeInsets.all(14);
                    final contentWidth = (constraints.maxWidth - 24)
                        .clamp(0.0, 720.0)
                        .toDouble();
                    final textScale = MediaQuery.textScalerOf(
                      context,
                    ).scale(1.0);
                    final availableCardWidth =
                        contentWidth - cardPadding.horizontal;
                    final tileNonTextWidth =
                        (tight ? 28 : 32) + (tight ? 16 : 20) + 8;
                    final colTextWidth =
                        ((availableCardWidth - 8) / 2) - tileNonTextWidth;
                    final useTwoColumns = (colTextWidth / textScale) >= 90;
                    final cs = Theme.of(context).colorScheme;
                    final surfaceStyle = appSurfaceStyleOf(context);
                    final cardGradient =
                        focusBackdrop.id == ThemeProvider.defaultFocusBackdropId
                        ? LinearGradient(
                            colors: [
                              color.withValues(alpha: 0.14),
                              cs.surface,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : LinearGradient(
                            colors: [
                              focusBackdrop.colors.first.withValues(
                                alpha: 0.22,
                              ),
                              focusBackdrop.colors.last.withValues(alpha: 0.14),
                              cs.surface,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          );

                    final card = AppSurfaceCard(
                      padding: cardPadding,
                      gradient: cardGradient,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: tight ? 38 : 44,
                                height: tight ? 38 : 44,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(
                                    surfaceStyle?.smallTileRadius ??
                                        DesignTokens.radiusControl,
                                  ),
                                ),
                                child: Icon(
                                  Icons.timer_outlined,
                                  color: color,
                                  size: tight ? 22 : 24,
                                ),
                              ),
                              if (focusBackdrop.id !=
                                  ThemeProvider.defaultFocusBackdropId) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: tight ? 7 : 9,
                                    vertical: tight ? 4 : 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: focusBackdrop.colors.first
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        focusBackdrop.icon,
                                        size: 13,
                                        color: focusBackdrop.colors.first,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        focusBackdrop.name,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: focusBackdrop.colors.first,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      slice.isCountUp
                                          ? MainUiCopy.pomodoroFreeTimer
                                          : typeLabel(slice.type),
                                      softWrap: true,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontSize: tight ? 15 : 17,
                                            color: cs.onSurface,
                                            fontWeight: FontWeight.normal,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${slice.completedSessions} ${s.focusCompletedSuffix}',
                                      softWrap: true,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: cs.onSurface,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Builder(
                                builder: (_) {
                                  final isBreak =
                                      slice.type == PomodoroType.shortBreak ||
                                      slice.type == PomodoroType.longBreak;
                                  final statusText = slice.isRunning
                                      ? (isBreak
                                            ? MainUiCopy.pomodoroStatusResting
                                            : MainUiCopy.pomodoroStatusFocusing)
                                      : (slice.isNotStarted
                                            ? MainUiCopy
                                                  .pomodoroStatusNotStarted
                                            : (isBreak
                                                  ? MainUiCopy
                                                        .pomodoroStatusBreakPaused
                                                  : MainUiCopy
                                                        .pomodoroStatusPaused));
                                  return Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: tight ? 8 : 10,
                                      vertical: tight ? 4 : 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      statusText,
                                      softWrap: true,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.normal,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          SizedBox(height: tight ? 6 : 10),
                          _PomodoroLiveTimer(
                            provider: provider,
                            color: color,
                            ringSize: ringSize,
                            tight: tight,
                            isCountUp: slice.isCountUp,
                            completedSessions: slice.completedSessions,
                            completedSuffix: s.focusCompletedSuffix,
                            timerLabel: s.focusTabTimer,
                            textColor: cs.onSurface,
                            formatTime: _formatTime,
                          ),
                          if (slice.taskName != null &&
                              slice.taskName!.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: tight ? 5 : 7),
                              child: Center(
                                child: GestureDetector(
                                  onTap: () => _editTaskName(
                                    context,
                                    provider,
                                    slice.taskName!,
                                  ),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width -
                                          96,
                                    ),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: tight ? 8 : 10,
                                        vertical: tight ? 4 : 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.surfaceContainerHighest
                                            .withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.assignment_outlined,
                                            size: 14,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.64,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              slice.taskName!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: cs.onSurface.withValues(
                                                  alpha: 0.72,
                                                ),
                                                fontSize: 12,
                                                fontWeight: FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          SizedBox(height: tight ? 6 : 9),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: [
                              ChoiceChip(
                                visualDensity: VisualDensity.compact,
                                avatar: const Icon(Icons.timer_outlined),
                                label: Text(MainUiCopy.pomodoroFreeTimer),
                                selected: slice.isCountUp,
                                onSelected: slice.isRunning
                                    ? null
                                    : (_) => provider.setCountUpMode(true),
                              ),
                              ChoiceChip(
                                key: const ValueKey(
                                  'pomodoro-default-duration',
                                ),
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  FocusRoomUiCopy.defaultDuration(
                                    slice.defaultFocusMinutes,
                                  ),
                                ),
                                selected:
                                    !slice.isCountUp &&
                                    slice.type == PomodoroType.focus &&
                                    slice.focusDurationUsesDefault,
                                onSelected: slice.isRunning
                                    ? null
                                    : (_) => _selectDuration(
                                        context,
                                        provider,
                                        durationOrigin,
                                        durationGeneration,
                                      ),
                              ),
                              ...[15, 25, 30, 45, 60, 90].map(
                                (min) => ChoiceChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    FocusRoomUiCopy.minutesSuffix(
                                      min,
                                      I18n.current,
                                    ),
                                  ),
                                  selected:
                                      !slice.isCountUp &&
                                      !slice.focusDurationUsesDefault &&
                                      slice.totalSeconds == min * 60 &&
                                      slice.type == PomodoroType.focus,
                                  onSelected: slice.isRunning
                                      ? null
                                      : (_) => _selectDuration(
                                          context,
                                          provider,
                                          durationOrigin,
                                          durationGeneration,
                                          minutes: min,
                                        ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: tight ? 6 : 8),
                          Selector<PomodoroProvider, _DailyGoalSlice>(
                            selector: (_, p) => _DailyGoalSlice(
                              persistedRevision: p.persistedRevision,
                              todayFocusMinutes: p.todayFocusMinutes,
                              dailyFocusGoalMinutes: p.dailyFocusGoalMinutes,
                              dailyFocusGoalProgress: p.dailyFocusGoalProgress,
                            ),
                            builder: (context, _, _) => _DailyFocusGoalRingTile(
                              key: const ValueKey('pomodoro_mobile_goal_ring'),
                              provider: provider,
                              color: color,
                              compact: tight,
                              onTap: () =>
                                  _showDailyGoalEditor(context, provider),
                            ),
                          ),
                          SizedBox(height: tight ? 6 : 8),
                          if (useTwoColumns)
                            Row(
                              children: [
                                Expanded(
                                  child: _FocusControlTile(
                                    icon: Icons.assignment_outlined,
                                    label: FocusRoomUiCopy.focusTaskLabel(
                                      I18n.current,
                                    ),
                                    subtitle: slice.taskName?.isNotEmpty == true
                                        ? slice.taskName!
                                        : FocusRoomUiCopy.selectTaskForRound(
                                            I18n.current,
                                          ),
                                    isUserContent:
                                        slice.taskName?.isNotEmpty == true,
                                    color: color,
                                    compact: tight,
                                    onTap: () => _showTaskPresetPicker(
                                      context,
                                      provider,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _WhiteNoiseControlTile(
                                    sound: slice.whiteNoiseSound,
                                    color: slice.whiteNoiseSound != 'none'
                                        ? color
                                        : cs.onSurfaceVariant,
                                    compact: tight,
                                    onTap: () => _showSoundPicker(
                                      context,
                                      provider,
                                      slice.whiteNoiseSound,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            _FocusControlTile(
                              icon: Icons.assignment_outlined,
                              label: FocusRoomUiCopy.focusTaskLabel(
                                I18n.current,
                              ),
                              subtitle: slice.taskName?.isNotEmpty == true
                                  ? slice.taskName!
                                  : FocusRoomUiCopy.selectTaskForRound(
                                      I18n.current,
                                    ),
                              isUserContent: slice.taskName?.isNotEmpty == true,
                              color: color,
                              compact: tight,
                              onTap: () =>
                                  _showTaskPresetPicker(context, provider),
                            ),
                            SizedBox(height: tight ? 6 : 8),
                            _WhiteNoiseControlTile(
                              sound: slice.whiteNoiseSound,
                              color: slice.whiteNoiseSound != 'none'
                                  ? color
                                  : cs.onSurfaceVariant,
                              compact: tight,
                              onTap: () => _showSoundPicker(
                                context,
                                provider,
                                slice.whiteNoiseSound,
                              ),
                            ),
                          ],
                          if (!kIsWeb) ...[
                            SizedBox(height: tight ? 6 : 8),
                            Selector<PomodoroProvider, _DndSlice>(
                              selector: (_, p) => _DndSlice(
                                autoEnableDnd: p.config.autoEnableDnd,
                                focusDndActive: p.focusDndActive,
                                accessGranted: p.focusDndStatus.accessGranted,
                                supported: p.focusDndStatus.supported,
                              ),
                              builder: (context, dnd, _) => _FocusDndTile(
                                enabled: dnd.autoEnableDnd,
                                active: dnd.focusDndActive,
                                accessGranted: dnd.accessGranted,
                                supported: dnd.supported,
                                compact: tight,
                                color: color,
                                onChanged: provider.setAutoEnableDnd,
                                onTap: () => _showDndSheet(context),
                              ),
                            ),
                            SizedBox(height: tight ? 6 : 8),
                            Selector<PomodoroProvider, _StrictFocusBadgeSlice>(
                              selector: (_, p) => _StrictFocusBadgeSlice(
                                strictFocusMode: p.config.strictFocusMode,
                                todayPenaltiesCount: p.todayPenalties.length,
                              ),
                              builder: (context, strict, _) => _StrictFocusTile(
                                enabled: strict.strictFocusMode,
                                todayCount: strict.todayPenaltiesCount,
                                compact: tight,
                                color: color,
                                onChanged: provider.setStrictFocusMode,
                                onTap: () => _showStrictFocusSheet(context),
                              ),
                            ),
                          ],
                          SizedBox(height: tight ? 6 : 8),
                          _ActiveFocusRoomTile(
                            focusRoomId: slice.focusRoomId,
                            compact: tight,
                            onTap: () => _showFocusRoomPicker(
                              context,
                              provider,
                              context.read<FocusRoomProvider>(),
                            ),
                          ),
                          SizedBox(height: tight ? 8 : 10),
                          Builder(
                            builder: (context) {
                              final isBreak =
                                  slice.type == PomodoroType.shortBreak ||
                                  slice.type == PomodoroType.longBreak;
                              final mainButtonTooltip = slice.isRunning
                                  ? (isBreak
                                        ? MainUiCopy.pomodoroActionPauseBreak
                                        : MainUiCopy.pomodoroActionPauseFocus)
                                  : (slice.isNotStarted
                                        ? (isBreak
                                              ? MainUiCopy
                                                    .pomodoroActionStartBreak
                                              : MainUiCopy
                                                    .pomodoroActionStartFocus)
                                        : (isBreak
                                              ? MainUiCopy
                                                    .pomodoroActionResumeBreak
                                              : MainUiCopy
                                                    .pomodoroActionResumeFocus));

                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton.filled(
                                    onPressed: () => _confirmStrictFocusExit(
                                      context,
                                      FocusPenaltyReason.reset,
                                      provider.resetTimer,
                                    ),
                                    tooltip: MainUiCopy.pomodoroActionReset,
                                    icon: const Icon(Icons.refresh),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      backgroundColor:
                                          cs.surfaceContainerHighest,
                                      foregroundColor: cs.onSurface,
                                    ),
                                  ),
                                  SizedBox(width: tight ? 14 : 18),
                                  SizedBox(
                                    width: tight ? 50 : 58,
                                    height: tight ? 50 : 58,
                                    child: FloatingActionButton(
                                      heroTag: 'pomodoro_main_timer_fab',
                                      tooltip: mainButtonTooltip,
                                      onPressed: provider.toggleTimer,
                                      backgroundColor: color,
                                      child: Icon(
                                        slice.isRunning
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        size: tight ? 28 : 30,
                                        color: appReadableForeground(
                                          color,
                                          Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: tight ? 14 : 18),
                                  IconButton.filled(
                                    onPressed: slice.isCountUp
                                        ? provider.finishCurrentSession
                                        : () => _confirmStrictFocusExit(
                                            context,
                                            FocusPenaltyReason.skip,
                                            provider.skipSession,
                                          ),
                                    tooltip: slice.isCountUp
                                        ? MainUiCopy.pomodoroActionFinishCountUp
                                        : MainUiCopy.pomodoroActionSkip,
                                    icon: Icon(
                                      slice.isCountUp
                                          ? Icons.stop
                                          : Icons.skip_next,
                                    ),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      backgroundColor:
                                          cs.surfaceContainerHighest,
                                      foregroundColor: cs.onSurface,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    );

                    final topPadding = compact ? 6.0 : 8.0;
                    final bottomPadding = compact ? 8.0 : 12.0;
                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        topPadding,
                        12,
                        bottomPadding,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(width: contentWidth, child: card),
                      ),
                    );
                  },
                );
              },
            ),
            // History tab
            _HistoryTab(),
            _FocusRoomTab(),
          ],
        ),
      ),
    );
  }

  Future<void> _activateRoom(
    PomodoroProvider pomodoro,
    FocusRoomProvider rooms,
    String roomId,
  ) async {
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    await rooms.joinRoom(roomId);
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      return;
    }
    await pomodoro.setFocusRoomId(roomId);
  }

  Future<void> _confirmStrictFocusExit(
    BuildContext context,
    FocusPenaltyReason reason,
    VoidCallback action,
  ) async {
    final provider = context.read<PomodoroProvider>();
    if (!provider.config.strictFocusMode ||
        !provider.state.isRunning ||
        provider.state.type != PomodoroType.focus) {
      action();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => AppDialog(
          title: Text(FocusRoomUiCopy.strictFocusConfirmTitle(reason, locale)),
          content: Text(
            FocusRoomUiCopy.strictFocusConfirmContent(locale),
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(FocusRoomUiCopy.keepFocusing(locale)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(FocusRoomUiCopy.confirmRecord(locale)),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) action();
  }

  Future<void> _showStrictFocusSheet(BuildContext context) async {
    final provider = context.read<PomodoroProvider>();
    final packageCtrl = TextEditingController(
      text: provider.config.distractingAppPackages.join('\n'),
    );
    try {
      await showAppModalSheet(
        context: context,
        builder: (ctx) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) =>
              Selector<PomodoroProvider, _StrictFocusSheetSlice>(
                selector: (_, p) => _StrictFocusSheetSlice(
                  strictFocusMode: p.config.strictFocusMode,
                  monitorDistractingApps: p.config.monitorDistractingApps,
                  accessibilityGranted:
                      p.focusDistractionStatus.accessibilityGranted,
                  accessGranted: p.focusDistractionStatus.accessGranted,
                  penaltiesCount: p.penalties.length,
                  todayPenaltiesCount: p.todayPenalties.length,
                  latestPenaltyId: p.penalties.isEmpty
                      ? null
                      : p.penalties.first.id,
                ),
                builder: (ctx, _, _) {
                  final provider = ctx.read<PomodoroProvider>();
                  final cs = Theme.of(ctx).colorScheme;
                  final today = provider.todayPenalties;
                  final recent = provider.penalties.take(8).toList();
              return AppModalSheet(
                title: FocusRoomUiCopy.strictFocusTitle(locale),
                subtitle: FocusRoomUiCopy.strictFocusSubtitle(locale),
                shiftForKeyboard: true,
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(FocusRoomUiCopy.done(locale)),
                  ),
                ],
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.lock_clock_outlined),
                      title: Text(FocusRoomUiCopy.enableStrictFocus(locale)),
                      subtitle: Text(
                        FocusRoomUiCopy.todayPenaltiesCount(
                          today.length,
                          locale,
                        ),
                      ),
                      value: provider.config.strictFocusMode,
                      onChanged: provider.setStrictFocusMode,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.app_blocking_outlined),
                      title: Text(
                        FocusRoomUiCopy.monitorDistractingApps(locale),
                      ),
                      subtitle: Text(
                        FocusRoomUiCopy.distractionStatusSubtitle(
                          accessibilityGranted: provider
                              .focusDistractionStatus
                              .accessibilityGranted,
                          accessGranted:
                              provider.focusDistractionStatus.accessGranted,
                          locale: locale,
                        ),
                      ),
                      value: provider.config.monitorDistractingApps,
                      onChanged: provider.setMonitorDistractingApps,
                    ),
                    TextField(
                      controller: packageCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: FocusRoomUiCopy.distractingPackageLabel(
                          locale,
                        ),
                        hintText: 'com.tencent.mm\ncom.ss.android.ugc.aweme',
                      ),
                      onChanged: (value) => unawaited(
                        provider.setDistractingAppPackages(
                          value
                              .split(RegExp(r'[\n,， ]+'))
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await provider.openFocusUsageAccessSettings();
                          await provider.refreshFocusDistractionStatus();
                        },
                        icon: const Icon(Icons.settings_outlined),
                        label: Text(FocusRoomUiCopy.usageAccessButton(locale)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await provider.openFocusAccessibilitySettings();
                          await provider.refreshFocusDistractionStatus();
                        },
                        icon: const Icon(Icons.accessibility_new_outlined),
                        label: Text(
                          FocusRoomUiCopy.accessibilityServiceButton(locale),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.42,
                        ),
                        borderRadius: BorderRadius.circular(
                          appSurfaceStyleOf(ctx)?.smallTileRadius ??
                              DesignTokens.radiusControl,
                        ),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                          width: 0.45,
                        ),
                      ),
                      child: Text(
                        FocusRoomUiCopy.strictFocusExplanation(locale),
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.68),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppSectionHeader(
                      title: FocusRoomUiCopy.recentPenaltiesHeader(locale),
                      subtitle: recent.isEmpty
                          ? FocusRoomUiCopy.noPenaltiesRecorded(locale)
                          : FocusRoomUiCopy.penaltiesCountSubtitle(
                              recent.length,
                              locale,
                            ),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 6),
                    if (recent.isEmpty)
                      Text(
                        FocusRoomUiCopy.emptyPenaltiesHint(locale),
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      )
                    else
                      ...recent.map(
                        (penalty) => _PenaltyListTile(penalty, locale: locale),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    } finally {
      packageCtrl.dispose();
    }
  }

  void _showFocusRoomPicker(
    BuildContext context,
    PomodoroProvider pomodoro,
    FocusRoomProvider rooms,
  ) {
    showAppModalSheet(
      context: context,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => AppModalSheet(
          title: FocusRoomUiCopy.selectRoomTitle(locale),
          subtitle: FocusRoomUiCopy.selectRoomSubtitle(locale),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showCreateRoomDialog(context, pomodoro, rooms);
              },
              icon: const Icon(Icons.add),
              label: Text(FocusRoomUiCopy.newRoomButton(locale)),
            ),
            if (pomodoro.state.focusRoomId != null)
              TextButton(
                onPressed: () {
                  unawaited(pomodoro.setFocusRoomId(null));
                  rooms.setActiveRoom(null);
                  Navigator.pop(ctx);
                },
                child: Text(FocusRoomUiCopy.doNotJoinThisRound(locale)),
              ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final room in rooms.rooms)
                _FocusRoomOptionTile(
                  room: room,
                  joined: rooms.joinedRoomIds.contains(room.id),
                  selected: pomodoro.state.focusRoomId == room.id,
                  locale: locale,
                  onTap: () async {
                    await _activateRoom(pomodoro, rooms, room.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateRoomDialog(
    BuildContext context,
    PomodoroProvider pomodoro,
    FocusRoomProvider rooms,
  ) async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final targetCtrl = TextEditingController(text: '300');
    final originGeneration = AccountLocalDataCleaner.accountDataGeneration;
    var submitting = false;
    await showControllerDialog<void>(
      context: context,
      controllers: [nameCtrl, descCtrl, targetCtrl],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => AppDialog(
            title: Text(FocusRoomUiCopy.createRoomTitle(locale)),
            shiftForKeyboard: true,
            content: _PomodoroDialogBody(
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
                    controller: targetCtrl,
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
                onPressed: submitting ? null : () => Navigator.pop(ctx),
                child: Text(FocusRoomUiCopy.cancel(locale)),
              ),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        if (submitting) return;
                        final route = ModalRoute.of(ctx);
                        if (!ctx.mounted ||
                            route == null ||
                            !route.isCurrent ||
                            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                              originGeneration,
                            )) {
                          return;
                        }
                        setDialogState(() => submitting = true);
                        final target =
                            int.tryParse(targetCtrl.text.trim()) ?? 300;
                        try {
                          final room = await rooms.createRoom(
                            name: nameCtrl.text,
                            description: descCtrl.text,
                            weeklyTargetMinutes: target,
                          );
                          if (!ctx.mounted ||
                              !route.isCurrent ||
                              !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                                originGeneration,
                              )) {
                            return;
                          }
                          await pomodoro.setFocusRoomId(room.id);
                          if (!ctx.mounted ||
                              !route.isCurrent ||
                              !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                                originGeneration,
                              )) {
                            return;
                          }
                          route.navigator?.pop();
                        } finally {
                          if (ctx.mounted && route.isCurrent) {
                            setDialogState(() => submitting = false);
                          }
                        }
                      },
                child: Text(FocusRoomUiCopy.create(locale)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editTaskName(
    BuildContext context,
    PomodoroProvider provider,
    String current,
  ) async {
    final ctrl = TextEditingController(text: current);
    final tagCtrl = TextEditingController(text: provider.state.tag ?? '');
    await showControllerDialog<void>(
      context: context,
      controllers: [ctrl, tagCtrl],
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => AppDialog(
          title: Text(FocusRoomUiCopy.focusTaskLabel(locale)),
          shiftForKeyboard: true,
          content: _PomodoroDialogBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    hintText: FocusRoomUiCopy.taskNameHint(locale),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagCtrl,
                  decoration: InputDecoration(
                    hintText: FocusRoomUiCopy.taskTagHint(locale),
                    prefixIcon: const Icon(Icons.label_outline),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(FocusRoomUiCopy.cancel(locale)),
            ),
            TextButton(
              onPressed: () {
                provider.setTaskName(null);
                provider.setTag(null);
                Navigator.pop(ctx);
              },
              child: Text(FocusRoomUiCopy.clearAction(locale)),
            ),
            FilledButton(
              onPressed: () {
                provider.setTaskName(ctrl.text);
                provider.setTag(tagCtrl.text);
                Navigator.pop(ctx);
              },
              child: Text(FocusRoomUiCopy.ok(locale)),
            ),
          ],
        ),
      ),
    );
  }

  IconData _soundIcon(String sound) => _soundIconForTile(sound);

  static IconData _soundIconForTile(String sound) {
    if (sound.startsWith(CustomFocusSoundProvider.idPrefix)) {
      return Icons.audio_file_outlined;
    }
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
      case 'night_rain':
        return Icons.nights_stay_outlined;
      case 'fan':
        return Icons.air;
      case 'deep_stream':
        return Icons.water;
      case 'thunderstorm':
        return Icons.thunderstorm_outlined;
      case 'storm_rain':
        return Icons.storm_outlined;
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
        return Icons.music_off;
    }
  }

  void _showSoundPicker(
    BuildContext context,
    PomodoroProvider provider,
    String currentSound,
  ) {
    final customProvider = context.read<CustomFocusSoundProvider>();
    const volumeOptions = <double>[0.4, 0.6, 0.8, 1.0];
    showAppModalSheet(
      context: context,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => AppModalSheet(
          title: FocusRoomUiCopy.selectWhiteNoiseTitle(locale),
          subtitle: FocusRoomUiCopy.selectWhiteNoiseSubtitle(locale),
          actions: [
            if (!kIsWeb)
              TextButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final imported = await customProvider.importAudio();
                  if (!ctx.mounted) return;
                  if (imported == null) return;
                  await provider.prepareSingleAmbientTrack(imported.id);
                  final previewStarted = await provider.setWhiteNoiseSound(
                    imported.id,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        previewStarted
                            ? FocusRoomUiCopy.importedAudioSuccess(
                                imported.label,
                                I18n.current,
                              )
                            : FocusRoomUiCopy.importedAudioPreviewFailed(
                                imported.label,
                                I18n.current,
                              ),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(FocusRoomUiCopy.importAudioButton(locale)),
              ),
          ],
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              Widget buildOptionTile(FocusSoundOption option) {
                final inMix = provider.ambientMixerTracks.containsKey(
                  option.id,
                );
                return _SoundOptionTile(
                  title: option.displayLabel(locale: locale),
                  icon: _soundIcon(option.id),
                  selected: currentSound == option.id,
                  previewTooltip: FocusRoomUiCopy.previewAudioTooltip(locale),
                  inMix: inMix,
                  onMixToggle: option.id == FocusSoundCatalog.none
                      ? null
                      : () async {
                          await provider.toggleMixerTrack(option.id);
                          if (ctx.mounted) setSheetState(() {});
                        },
                  onPreview: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await provider.prepareSingleAmbientTrack(option.id);
                    final previewStarted = await provider.setWhiteNoiseSound(
                      option.id,
                    );
                    if (!ctx.mounted) return;
                    setSheetState(() {});
                    if (!previewStarted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            FocusRoomUiCopy.soundPreviewFailed(I18n.current),
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await provider.prepareSingleAmbientTrack(option.id);
                    final previewStarted = await provider.setWhiteNoiseSound(
                      option.id,
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!previewStarted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            FocusRoomUiCopy.soundPreviewFailed(I18n.current),
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                );
              }

              return AnimatedBuilder(
                animation: provider,
                builder: (context, _) {
                  final mixerEntries = provider.ambientMixerTracks.entries
                      .toList(growable: false);
                  final isEn = locale == AppLocale.en;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          FocusRoomUiCopy.soundPreviewHint(locale),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.58),
                              ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final value in volumeOptions)
                              ChoiceChip(
                                label: Text('${(value * 100).round()}%'),
                                selected:
                                    provider.config.focusSoundVolume == value,
                                onSelected: (_) async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  final previewStarted = await provider
                                      .setFocusSoundVolume(value);
                                  if (!ctx.mounted) return;
                                  setSheetState(() {});
                                  if (!previewStarted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          FocusRoomUiCopy.soundVolumePreviewFailed(
                                            I18n.current,
                                          ),
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 18),
                      Container(
                        key: const ValueKey('pomodoro_mobile_mixer_panel'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(
                            appSurfaceStyleOf(context)?.smallTileRadius ??
                                DesignTokens.radiusControl,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.layers_outlined,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    isEn
                                        ? 'Multi-track Ambient Mixer (${mixerEntries.length}/${PomodoroProvider.maxAmbientMixerTracks})'
                                        : '多音轨混音 (${mixerEntries.length}/${PomodoroProvider.maxAmbientMixerTracks})',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                if (mixerEntries.isNotEmpty)
                                  TextButton(
                                    onPressed: () async {
                                      await provider.toggleMixerAudition();
                                      if (ctx.mounted) setSheetState(() {});
                                    },
                                    child: Text(
                                      provider.isMixerAuditioning
                                          ? (isEn ? 'Stop' : '停止')
                                          : (isEn ? 'Play mix' : '试听混音'),
                                    ),
                                  ),
                                if (mixerEntries.isNotEmpty)
                                  TextButton(
                                    onPressed: () async {
                                      await provider.clearMixerTracks();
                                      if (ctx.mounted) setSheetState(() {});
                                    },
                                    child: Text(isEn ? 'Clear' : '清空'),
                                  ),
                              ],
                            ),
                            if (mixerEntries.isEmpty)
                              Text(
                                isEn
                                    ? 'Tap the layer icon on 2+ sounds below to blend tracks.'
                                    : '点击下方音轨右侧叠加图标，可自由混合 2-4 条环境音轨并独立调音。',
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            else
                              for (final entry in mixerEntries)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 82,
                                        child: Text(
                                          FocusSoundCatalog.labelFor(
                                            entry.key,
                                            locale: locale,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        child: Slider(
                                          value: entry.value.clamp(0.1, 1.0),
                                          min: 0.1,
                                          max: 1.0,
                                          onChanged: (v) async {
                                            await provider.setMixerTrackVolume(
                                              entry.key,
                                              v,
                                            );
                                            if (ctx.mounted) {
                                              setSheetState(() {});
                                            }
                                          },
                                        ),
                                      ),
                                      Text(
                                        '${(entry.value * 100).round()}%',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 16,
                                        icon: const Icon(Icons.close),
                                        onPressed: () async {
                                          await provider.toggleMixerTrack(
                                            entry.key,
                                          );
                                          if (ctx.mounted) setSheetState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                          ],
                        ),
                      ),
                      const Divider(height: 18),
                      buildOptionTile(FocusSoundCatalog.noneOption),
                      for (final group in FocusSoundCatalog.groupedOptions) ...[
                        const Divider(height: 16),
                        AppSectionHeader(
                          title: group.category.displayLabel(locale: locale),
                          padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                        ),
                        for (final option in group.options)
                          buildOptionTile(option),
                      ],
                      if (customProvider.sounds.isNotEmpty) ...[
                        const Divider(height: 18),
                        AppSectionHeader(
                          title: FocusRoomUiCopy.customAudioLabel(locale),
                          padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                        ),
                        for (final sound in customProvider.sounds)
                          _SoundOptionTile(
                            title: sound.label,
                            subtitle: FocusRoomUiCopy.customAudioLabel(locale),
                            icon: _soundIcon(sound.id),
                            selected: currentSound == sound.id,
                            previewTooltip: FocusRoomUiCopy.previewAudioTooltip(
                              locale,
                            ),
                            deleteTooltip:
                                FocusRoomUiCopy.deleteCustomAudioTooltip(
                                  locale,
                                ),
                            onPreview: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await provider.prepareSingleAmbientTrack(
                                sound.id,
                              );
                              final previewStarted = await provider.setWhiteNoiseSound(
                                sound.id,
                              );
                              if (!ctx.mounted) return;
                              if (!previewStarted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      FocusRoomUiCopy.customSoundPreviewFailed(
                                        I18n.current,
                                      ),
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                            onTap: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await provider.prepareSingleAmbientTrack(
                                sound.id,
                              );
                              final previewStarted = await provider.setWhiteNoiseSound(
                                sound.id,
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!previewStarted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      FocusRoomUiCopy.customSoundPreviewFailed(
                                        I18n.current,
                                      ),
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                            onDelete: () async {
                              await customProvider.remove(sound.id);
                              if (provider.state.whiteNoiseSound == sound.id) {
                                await provider.prepareSingleAmbientTrack(
                                  FocusSoundCatalog.none,
                                );
                                await provider.setWhiteNoiseSound(
                                  FocusSoundCatalog.none,
                                );
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                          ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showTaskPresetPicker(BuildContext context, PomodoroProvider provider) {
    final activeTodos =
        context.read<TodoProvider?>()?.activeTodos ?? const <TodoItem>[];
    showAppModalSheet(
      context: context,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) {
          final isEn = locale == AppLocale.en;
          final presets = FocusRoomUiCopy.taskPresets(locale);
          return AppModalSheet(
            title: FocusRoomUiCopy.focusTaskLabel(locale),
            subtitle: FocusRoomUiCopy.focusTaskPresetsSubtitle(locale),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _editTaskName(
                    context,
                    provider,
                    provider.state.taskName ?? '',
                  );
                },
                child: Text(FocusRoomUiCopy.manualInputButton(locale)),
              ),
              if (provider.state.taskName?.isNotEmpty == true)
                TextButton(
                  onPressed: () {
                    provider.setTaskName(null);
                    Navigator.pop(ctx);
                  },
                  child: Text(FocusRoomUiCopy.clearAction(locale)),
                ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activeTodos.isNotEmpty) ...[
                  Text(
                    isEn ? 'Active Todos' : '进行中的待办任务',
                    style: Theme.of(ctx).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final todo in activeTodos.take(12))
                        ActionChip(
                          key: ValueKey('pomodoro_todo_pick_${todo.id}'),
                          avatar: const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                          ),
                          label: Text(todo.title),
                          onPressed: () {
                            provider.setTaskName(todo.title);
                            Navigator.pop(ctx);
                          },
                        ),
                    ],
                  ),
                  const Divider(height: 20),
                ],
                Text(
                  isEn ? 'Quick Presets' : '快捷场景预设',
                  style: Theme.of(ctx).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in presets)
                      ActionChip(
                        avatar: const Icon(Icons.assignment_outlined, size: 16),
                        label: Text(preset),
                        onPressed: () {
                          provider.setTaskName(preset);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showDailyGoalEditor(
    BuildContext context,
    PomodoroProvider provider,
  ) async {
    var selected = provider.dailyFocusGoalMinutes;
    final customCtrl = TextEditingController(text: '$selected');
    try {
      final target = await showDialog<int>(
        context: context,
        builder: (ctx) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) {
            final isEn = locale == AppLocale.en;
            return StatefulBuilder(
              builder: (ctx, setSt) => AppDialog(
                title: Text(isEn ? 'Daily focus goal' : '每日专注目标'),
                content: _PomodoroDialogBody(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final mins in const [30, 60, 90, 120, 180, 240])
                            ChoiceChip(
                              label: Text(isEn ? '${mins}m' : '$mins 分钟'),
                              selected: selected == mins,
                              onSelected: (_) => setSt(() {
                                selected = mins;
                                customCtrl.text = '$mins';
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: customCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: isEn
                              ? 'Target minutes (10-720)'
                              : '目标时长（分钟，10-720）',
                        ),
                        onChanged: (v) {
                          final parsed = int.tryParse(v.trim());
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
                    child: Text(I18n.tr('action.cancel')),
                  ),
                  FilledButton(
                    onPressed: () {
                      final parsed =
                          int.tryParse(customCtrl.text.trim()) ?? selected;
                      Navigator.of(ctx).pop(parsed.clamp(10, 720).toInt());
                    },
                    child: Text(I18n.tr('action.save')),
                  ),
                ],
              ),
            );
          },
        ),
      );
      if (target != null && mounted) {
        await provider.setDailyFocusGoalMinutes(target);
      }
    } finally {
      customCtrl.dispose();
    }
  }

  void _showDndSheet(BuildContext context) {
    showAppModalSheet(
      context: context,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => Selector<PomodoroProvider, _DndSheetSlice>(
          selector: (_, p) => _DndSheetSlice(
            autoEnableDnd: p.config.autoEnableDnd,
            supported: p.focusDndStatus.supported,
            accessGranted: p.focusDndStatus.accessGranted,
          ),
          builder: (ctx, _, _) {
            final provider = ctx.read<PomodoroProvider>();
            final cs = Theme.of(ctx).colorScheme;
            return AppModalSheet(
              title: FocusRoomUiCopy.focusDndSheetTitle(locale),
              subtitle: FocusRoomUiCopy.focusDndSheetSubtitle(locale),
              actions: [
                TextButton(
                  onPressed: () async {
                    await provider.refreshFocusDndStatus();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(FocusRoomUiCopy.done(locale)),
                ),
                FilledButton.icon(
                  onPressed: provider.focusDndStatus.supported
                      ? () => provider.openFocusDndSettings()
                      : null,
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(FocusRoomUiCopy.authorizeButton(locale)),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.do_not_disturb_on_outlined),
                    title: Text(FocusRoomUiCopy.autoEnableDndSwitch(locale)),
                    subtitle: Text(
                      provider.focusDndStatus.accessGranted
                          ? FocusRoomUiCopy.dndPermissionGranted(locale)
                          : FocusRoomUiCopy.dndPermissionRequired(locale),
                    ),
                    value: provider.config.autoEnableDnd,
                    onChanged: provider.setAutoEnableDnd,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(
                        appSurfaceStyleOf(ctx)?.smallTileRadius ??
                            DesignTokens.radiusControl,
                      ),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                        width: 0.45,
                      ),
                    ),
                    child: Text(
                      provider.focusDndStatus.supported
                          ? FocusRoomUiCopy.dndSupportedExplanation(locale)
                          : FocusRoomUiCopy.dndUnsupportedExplanation(locale),
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.68),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FocusRoomTile extends StatelessWidget {
  final String roomName;
  final String subtitle;
  final Color color;
  final bool compact;
  final VoidCallback onTap;
  final AppLocale? locale;

  const _FocusRoomTile({
    required this.roomName,
    required this.subtitle,
    required this.color,
    required this.compact,
    required this.onTap,
    this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tileRadius =
        appSurfaceStyleOf(context)?.smallTileRadius ?? DesignTokens.radiusControl;
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: InkWell(
          borderRadius: BorderRadius.circular(tileRadius),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(tileRadius),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.16),
                width: 0.45,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 8 : 10,
                  compact ? 6 : 8,
                  compact ? 8 : 10,
                  compact ? 6 : 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: compact ? 28 : 32,
                      height: compact ? 28 : 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                      ),
                      child: Icon(
                        Icons.groups_2_outlined,
                        color: color,
                        size: compact ? 15 : 17,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            FocusRoomUiCopy.studyRoomTitle(locale),
                            softWrap: true,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 11,
                                  height: 1.05,
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.normal,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            roomName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontSize: compact ? 12 : 13,
                                  height: 1.08,
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.normal,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            softWrap: true,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: cs.onSurface,
                                  fontSize: 11,
                                  height: 1.25,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveFocusRoomTileViewModel {
  final String roomName;
  final String subtitle;
  final int colorValue;
  final AppLocale locale;

  const _ActiveFocusRoomTileViewModel({
    required this.roomName,
    required this.subtitle,
    required this.colorValue,
    required this.locale,
  });

  @override
  bool operator ==(Object other) {
    return other is _ActiveFocusRoomTileViewModel &&
        other.roomName == roomName &&
        other.subtitle == subtitle &&
        other.colorValue == colorValue &&
        other.locale == locale;
  }

  @override
  int get hashCode => Object.hash(roomName, subtitle, colorValue, locale);
}

class _ActiveFocusRoomTile extends StatelessWidget {
  final String? focusRoomId;
  final bool compact;
  final VoidCallback onTap;

  const _ActiveFocusRoomTile({
    required this.focusRoomId,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fallbackColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) =>
          Selector<FocusRoomProvider, _ActiveFocusRoomTileViewModel>(
            selector: (_, rooms) {
              final activeRoom =
                  rooms.roomById(focusRoomId) ?? rooms.activeRoom;
              return _ActiveFocusRoomTileViewModel(
                roomName:
                    activeRoom?.nameFor(locale) ??
                    FocusRoomUiCopy.noRoomJoined(locale),
                subtitle: FocusRoomUiCopy.activeRoomTileSubtitle(
                  activeRoom != null,
                  locale,
                ),
                colorValue: activeRoom?.accentColor ?? fallbackColor.toARGB32(),
                locale: locale,
              );
            },
            builder: (context, state, _) => _FocusRoomTile(
              roomName: state.roomName,
              subtitle: state.subtitle,
              color: Color(state.colorValue),
              compact: compact,
              onTap: onTap,
              locale: state.locale,
            ),
          ),
    );
  }
}

class _DailyFocusGoalRingTile extends StatelessWidget {
  final PomodoroProvider provider;
  final Color color;
  final bool compact;
  final VoidCallback onTap;

  const _DailyFocusGoalRingTile({
    super.key,
    required this.provider,
    required this.color,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final isEn = locale == AppLocale.en;
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final tileRadius =
            appSurfaceStyleOf(context)?.smallTileRadius ??
            DesignTokens.radiusControl;
        final todayMins = provider.todayFocusMinutes;
        final goalMins = provider.dailyFocusGoalMinutes;
        final progress = provider.dailyFocusGoalProgress;
        final pct = (progress * 100).round();
        final ringDim = compact ? 28.0 : 34.0;
        final completedColor = isDark
            ? const Color(0xFF66BB6A)
            : DesignTokens.defaultSuccess;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(tileRadius),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(tileRadius),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.16),
                  width: 0.45,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: compact ? 5 : 7,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: ringDim,
                      height: ringDim,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 3.2,
                            backgroundColor: color.withValues(alpha: 0.14),
                            color: progress >= 1.0 ? completedColor : color,
                          ),
                          Text(
                            '$pct%',
                            style: TextStyle(
                              fontSize: compact ? 8.5 : 9.5,
                              color: cs.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEn ? 'Daily Focus Goal' : '今日专注目标',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            isEn
                                ? '$todayMins / $goalMins min'
                                : '$todayMins / $goalMins 分钟',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: compact ? 12 : 13,
                              color: cs.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.tune_outlined,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WhiteNoiseControlTile extends StatelessWidget {
  final String sound;
  final Color color;
  final bool compact;
  final VoidCallback onTap;

  const _WhiteNoiseControlTile({
    required this.sound,
    required this.color,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final mixerIds = context.select<PomodoroProvider, List<String>>(
          (p) => p.activeMixerTrackIds,
        );
        final isCustom = context.select<CustomFocusSoundProvider, bool>(
          (custom) => custom.isCustomSound(sound),
        );
        final singleLabel = context.select<CustomFocusSoundProvider, String>((
          custom,
        ) {
          return custom.isCustomSound(sound)
              ? custom.labelFor(sound)
              : FocusSoundCatalog.labelFor(sound, locale: locale);
        });
        final label = mixerIds.length >= 2
            ? mixerIds
                  .take(2)
                  .map((id) => FocusSoundCatalog.labelFor(id, locale: locale))
                  .join(' + ') +
              (mixerIds.length > 2 ? ' +${mixerIds.length - 2}' : '')
            : singleLabel;
        return _FocusControlTile(
          icon: mixerIds.length >= 2
              ? Icons.layers_outlined
              : _PomodoroScreenState._soundIconForTile(sound),
          label: FocusRoomUiCopy.whiteNoiseLabel(locale),
          subtitle: label,
          isUserContent: isCustom,
          color: mixerIds.length >= 2 ? color : color,
          compact: compact,
          onTap: onTap,
        );
      },
    );
  }
}

class _StrictFocusTile extends StatelessWidget {
  final bool enabled;
  final int todayCount;
  final bool compact;
  final Color color;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap;

  const _StrictFocusTile({
    required this.enabled,
    required this.todayCount,
    required this.compact,
    required this.color,
    required this.onChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final cs = Theme.of(context).colorScheme;
        final effectiveColor = enabled ? color : cs.onSurfaceVariant;
        final subtitle = FocusRoomUiCopy.strictFocusTileSubtitle(
          enabled,
          todayCount,
          locale,
        );
        final tileRadius =
            appSurfaceStyleOf(context)?.smallTileRadius ??
            DesignTokens.radiusControl;
        return Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: InkWell(
              borderRadius: BorderRadius.circular(tileRadius),
              onTap: onTap,
              child: Ink(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(tileRadius),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.16),
                    width: 0.45,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 8 : 10,
                      compact ? 5 : 7,
                      compact ? 4 : 6,
                      compact ? 5 : 7,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: compact ? 28 : 32,
                          height: compact ? 28 : 32,
                          decoration: BoxDecoration(
                            color: effectiveColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusSm,
                            ),
                          ),
                          child: Icon(
                            Icons.lock_clock_outlined,
                            color: effectiveColor,
                            size: compact ? 15 : 17,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                FocusRoomUiCopy.strictFocusTitle(locale),
                                softWrap: true,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontSize: 11,
                                      height: 1.05,
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.normal,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                softWrap: true,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontSize: compact ? 12 : 13,
                                      height: 1.08,
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.normal,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: enabled,
                          onChanged: onChanged,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PenaltyListTile extends StatelessWidget {
  final PomodoroFocusPenalty penalty;
  final AppLocale? locale;

  const _PenaltyListTile(this.penalty, {this.locale});

  @override
  Widget build(BuildContext context) {
    final currentLocale = locale ?? I18n.current;
    final cs = Theme.of(context).colorScheme;
    final time =
        '${penalty.occurredAt.month}/${penalty.occurredAt.day} '
        '${penalty.occurredAt.hour.toString().padLeft(2, '0')}:'
        '${penalty.occurredAt.minute.toString().padLeft(2, '0')}';
    final minutes = (penalty.affectedSeconds / 60).ceil().clamp(1, 1440);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        ),
        child: Icon(Icons.warning_amber_rounded, color: cs.error, size: 19),
      ),
      title: Text(penalty.reason.labelFor(currentLocale)),
      subtitle: Text(
        [
          time,
          FocusRoomUiCopy.minutesSuffix(minutes, currentLocale),
          if (penalty.taskName?.isNotEmpty == true) penalty.taskName!,
        ].join(' · '),
      ),
    );
  }
}

class _FocusRoomOptionTile extends StatelessWidget {
  final FocusRoom room;
  final bool joined;
  final bool selected;
  final VoidCallback onTap;
  final AppLocale? locale;

  const _FocusRoomOptionTile({
    required this.room,
    required this.joined,
    required this.selected,
    required this.onTap,
    this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final currentLocale = locale ?? I18n.current;
    final cs = Theme.of(context).colorScheme;
    final color = Color(room.accentColor);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(
            appSurfaceStyleOf(context)?.smallTileRadius ??
                DesignTokens.radiusControl,
          ),
        ),
        child: Icon(Icons.groups_2_outlined, color: color, size: 20),
      ),
      title: Text(room.nameFor(currentLocale)),
      subtitle: Text(
        FocusRoomUiCopy.roomGoalSubtitle(
          room.descriptionFor(currentLocale),
          room.weeklyTargetSeconds ~/ 60,
          currentLocale,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, color: cs.primary)
          : joined
          ? Text(FocusRoomUiCopy.joinedBadge(currentLocale))
          : Text(FocusRoomUiCopy.joinAction(currentLocale)),
      onTap: onTap,
    );
  }
}

class _MaybePomodoroBackground extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const _MaybePomodoroBackground({required this.enabled, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return BrandBackground(child: child);
  }
}

class _PomodoroLiveTimer extends StatelessWidget {
  final PomodoroProvider provider;
  final Color color;
  final double ringSize;
  final bool tight;
  final bool isCountUp;
  final int completedSessions;
  final String completedSuffix;
  final String timerLabel;
  final Color textColor;
  final String Function(int seconds) formatTime;

  const _PomodoroLiveTimer({
    required this.provider,
    required this.color,
    required this.ringSize,
    required this.tight,
    required this.isCountUp,
    required this.completedSessions,
    required this.completedSuffix,
    required this.timerLabel,
    required this.textColor,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: SizedBox(
            width: ringSize,
            height: ringSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RepaintBoundary(
                  child: PomodoroTimerRingBackdrop(
                    size: ringSize,
                    color: color,
                    surfaceColor: surfaceColor,
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: provider.timerTicks,
                  builder: (context, _, _) {
                    final state = provider.state;
                    return PomodoroTimerRing(
                      progress: state.progress,
                      timeText: formatTime(state.remainingSeconds),
                      color: color,
                      size: ringSize,
                      countUp: state.isCountUp,
                      showOuterDecoration: false,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: tight ? 4 : 6),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              isCountUp
                  ? '${MainUiCopy.pomodoroFreeTimer} · $completedSessions $completedSuffix'
                  : '$timerLabel · $completedSessions $completedSuffix',
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(
                color: textColor,
                fontSize: tight ? 12 : 13,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FocusRoomTab extends StatefulWidget {
  const _FocusRoomTab();

  @override
  State<_FocusRoomTab> createState() => _FocusRoomTabState();
}

class _FocusRoomTabState extends State<_FocusRoomTab>
    with AutomaticKeepAliveClientMixin<_FocusRoomTab> {
  String? _lastRefreshKey;
  bool _refreshScheduled = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rooms = context.read<FocusRoomProvider>();
    final pomodoroRevision = context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final focusRoomId = context.select<PomodoroProvider, String?>(
      (provider) => provider.state.focusRoomId,
    );
    final rawUsername = context.select<AuthProvider, String?>(
      (auth) => auth.state.username?.trim(),
    );
    final joinedRefreshKey = context.select<FocusRoomProvider, String>((
      provider,
    ) {
      final ids = provider.joinedRoomIds.toList()..sort();
      return ids.join('|');
    });
    final activeRoom = context.select<FocusRoomProvider, FocusRoom?>(
      (provider) => provider.roomById(focusRoomId),
    );
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final displayName = rawUsername?.isNotEmpty == true
            ? rawUsername!
            : FocusRoomUiCopy.selfDisplayNameFallback(locale);
        final activeRoomName = activeRoom?.nameFor(locale);
        _scheduleRoomRefresh(
          context,
          rooms,
          pomodoroRevision,
          displayName,
          joinedRefreshKey,
          refreshIdentity: rawUsername ?? '',
        );

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesktopTokens.secondaryMaxContentWidth,
            ),
            child: ListView(
              key: const PageStorageKey<String>('focus_room_tab_scroll'),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              children: [
                _FocusSocialLeaderboardSection(
                  displayName: displayName,
                  onManageFriends: () => _showFocusFriendSheet(
                    context,
                    context.read<FocusRoomProvider>(),
                  ),
                ),
                const SizedBox(height: 12),
                _JoinedFocusRoomRankingSection(
                  activeRoomName: activeRoomName,
                  displayName: displayName,
                  onAcceptInvite: () => _showAcceptFocusRoomInviteDialog(
                    context,
                    context.read<FocusRoomProvider>(),
                    context.read<PomodoroProvider>(),
                    displayName,
                  ),
                ),
                const SizedBox(height: 12),
                _FocusRoomCatalogSection(
                  displayName: displayName,
                  onManageInvites: (room) => _showFocusRoomInviteSheet(
                    context,
                    context.read<FocusRoomProvider>(),
                    room,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scheduleRoomRefresh(
    BuildContext context,
    FocusRoomProvider rooms,
    int pomodoroRevision,
    String displayName,
    String joinedRefreshKey, {
    required String refreshIdentity,
  }) {
    final refreshKey = [
      joinedRefreshKey,
      pomodoroRevision,
      refreshIdentity,
    ].join('::');
    if (_lastRefreshKey == refreshKey || _refreshScheduled) return;
    _lastRefreshKey = refreshKey;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted) return;
      final roomProvider = context.read<FocusRoomProvider>();
      final pomodoroProvider = context.read<PomodoroProvider>();
      roomProvider.watchRealtimeRankings();
      unawaited(roomProvider.loadFocusFriendsAndRanking());
      unawaited(roomProvider.loadGlobalRanking());
      unawaited(
        roomProvider.syncRemoteRankings(
          pomodoroProvider.sessions,
          displayName: displayName,
          active: true,
        ),
      );
    });
  }

  Future<void> _showFocusRoomInviteSheet(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusRoom room,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    try {
      await rooms.loadInvitesForRoom(room.id);
    } catch (e) {
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!context.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      return;
    }
    showAppModalSheet<void>(
      context: context,
      builder: (sheetContext) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (sheetContext, locale, _) => Consumer<FocusRoomProvider>(
          builder: (sheetContext, provider, _) {
            final invites = provider.invitesForRoom(room.id);
            return AppModalSheet(
              title: FocusRoomUiCopy.inviteManagementTitle(locale),
              subtitle: room.nameFor(locale),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: Text(FocusRoomUiCopy.done(locale)),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (provider.remoteLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: provider.remoteLoading
                          ? null
                          : () => _showCreateFocusRoomInviteDialog(
                              context,
                              provider,
                              room,
                            ),
                      icon: const Icon(Icons.add_link_outlined),
                      label: Text(FocusRoomUiCopy.newInviteCodeButton(locale)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (invites.isEmpty)
                    Text(
                      FocusRoomUiCopy.noInvitesCreated(locale),
                      style: Theme.of(sheetContext).textTheme.bodySmall
                          ?.copyWith(
                            color: Theme.of(
                              sheetContext,
                            ).colorScheme.onSurface.withValues(alpha: 0.62),
                          ),
                    )
                  else
                    ...invites.map(
                      (invite) => _FocusRoomInviteTile(
                        invite: invite,
                        meta: _focusRoomInviteMeta(invite, locale),
                        active: _focusRoomInviteUsable(invite),
                        locale: locale,
                        onCopy: () =>
                            _copyExistingFocusRoomInvite(context, invite),
                        onRevoke: invite.revoked
                            ? null
                            : () => _revokeFocusRoomInvite(
                                context,
                                provider,
                                room,
                                invite,
                              ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _createAndCopyFocusRoomInvite(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusRoom room,
    DateTime? expiresAt,
    int maxUses,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    try {
      final invite = await rooms.createInviteForRoom(
        room.id,
        expiresAt: expiresAt,
        maxUses: maxUses,
      );
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      await Clipboard.setData(ClipboardData(text: invite.code));
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            FocusRoomUiCopy.copiedInviteSnackBar(invite.code, I18n.current),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showCreateFocusRoomInviteDialog(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusRoom room,
  ) {
    var expiryDays = 0;
    var maxUses = 0;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (dialogContext, locale, _) => StatefulBuilder(
          builder: (dialogContext, setState) => AppDialog(
            title: Text(FocusRoomUiCopy.newInviteDialogTitle(locale)),
            shiftForKeyboard: true,
            content: _PomodoroDialogBody(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppDropdownField<int>(
                    key: ValueKey('invite_expiry_${locale.name}_$expiryDays'),
                    initialValue: expiryDays,
                    decoration: InputDecoration(
                      labelText: FocusRoomUiCopy.validityLabel(locale),
                      prefixIcon: const Icon(Icons.event_available_outlined),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text(FocusRoomUiCopy.neverExpiresOption(locale)),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Text(FocusRoomUiCopy.daysOption(1, locale)),
                      ),
                      DropdownMenuItem(
                        value: 7,
                        child: Text(FocusRoomUiCopy.daysOption(7, locale)),
                      ),
                      DropdownMenuItem(
                        value: 30,
                        child: Text(FocusRoomUiCopy.daysOption(30, locale)),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => expiryDays = value ?? 0),
                  ),
                  const SizedBox(height: 10),
                  AppDropdownField<int>(
                    key: ValueKey('invite_uses_${locale.name}_$maxUses'),
                    initialValue: maxUses,
                    decoration: InputDecoration(
                      labelText: FocusRoomUiCopy.usageLimitLabel(locale),
                      prefixIcon: const Icon(
                        Icons.confirmation_number_outlined,
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text(
                          FocusRoomUiCopy.unlimitedUsesOption(locale),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Text(FocusRoomUiCopy.usesCountOption(1, locale)),
                      ),
                      DropdownMenuItem(
                        value: 5,
                        child: Text(FocusRoomUiCopy.usesCountOption(5, locale)),
                      ),
                      DropdownMenuItem(
                        value: 10,
                        child: Text(
                          FocusRoomUiCopy.usesCountOption(10, locale),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 50,
                        child: Text(
                          FocusRoomUiCopy.usesCountOption(50, locale),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => maxUses = value ?? 0),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(FocusRoomUiCopy.cancel(locale)),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final generation =
                      AccountLocalDataCleaner.accountDataGeneration;
                  final expiresAt = expiryDays <= 0
                      ? null
                      : DateTime.now().add(Duration(days: expiryDays));
                  await _createAndCopyFocusRoomInvite(
                    context,
                    rooms,
                    room,
                    expiresAt,
                    maxUses,
                  );
                  if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                    generation,
                  )) {
                    return;
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                icon: const Icon(Icons.add_link_outlined),
                label: Text(FocusRoomUiCopy.createAndCopyButton(locale)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyExistingFocusRoomInvite(
    BuildContext context,
    FocusRoomInvite invite,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: invite.code));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          FocusRoomUiCopy.copiedInviteSnackBar(invite.code, I18n.current),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _revokeFocusRoomInvite(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusRoom room,
    FocusRoomInvite invite,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    try {
      await rooms.revokeInviteForRoom(room.id, invite.id);
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(FocusRoomUiCopy.inviteRevokedSnackBar(I18n.current)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _focusRoomInviteMeta(FocusRoomInvite invite, [AppLocale? locale]) {
    final status = invite.revoked
        ? FocusRoomUiCopy.inviteStatusRevoked(locale)
        : _focusRoomInviteDepleted(invite)
        ? FocusRoomUiCopy.inviteStatusDepleted(locale)
        : invite.expiresAt == null
        ? FocusRoomUiCopy.inviteStatusPermanent(locale)
        : invite.expiresAt!.isBefore(DateTime.now())
        ? FocusRoomUiCopy.inviteStatusExpired(locale)
        : FocusRoomUiCopy.inviteValidUntil(
            _formatShortDateTime(invite.expiresAt!),
            locale,
          );
    final usage = invite.maxUses <= 0
        ? FocusRoomUiCopy.inviteUnlimitedUsage(locale)
        : FocusRoomUiCopy.inviteUsageCount(
            invite.usedCount,
            invite.maxUses,
            locale,
          );
    final lastUsed = invite.lastUsedAt == null
        ? null
        : FocusRoomUiCopy.inviteLastUsed(
            _formatShortDateTime(invite.lastUsedAt!),
            locale,
          );
    final created = invite.createdAt == null
        ? null
        : FocusRoomUiCopy.inviteCreatedAt(
            _formatShortDateTime(invite.createdAt!),
            locale,
          );
    return [status, usage, ?lastUsed, ?created].join(' · ');
  }

  bool _focusRoomInviteUsable(FocusRoomInvite invite) {
    if (invite.revoked) return false;
    if (_focusRoomInviteDepleted(invite)) return false;
    final expiresAt = invite.expiresAt;
    return expiresAt == null || expiresAt.isAfter(DateTime.now());
  }

  bool _focusRoomInviteDepleted(FocusRoomInvite invite) {
    return invite.maxUses > 0 && invite.usedCount >= invite.maxUses;
  }

  String _formatShortDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _showAcceptFocusRoomInviteDialog(
    BuildContext context,
    FocusRoomProvider rooms,
    PomodoroProvider pomodoro,
    String displayName,
  ) {
    final codeCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => AppDialog(
          title: Text(FocusRoomUiCopy.enterInviteCodeDialogTitle(locale)),
          shiftForKeyboard: true,
          content: _PomodoroDialogBody(
            child: TextField(
              controller: codeCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: FocusRoomUiCopy.studyRoomInviteCodeLabel(locale),
                prefixIcon: const Icon(Icons.key_outlined),
              ),
              onSubmitted: (_) => _acceptFocusRoomInvite(
                context,
                ctx,
                rooms,
                pomodoro,
                codeCtrl.text,
                displayName,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(FocusRoomUiCopy.cancel(locale)),
            ),
            FilledButton.icon(
              onPressed: () => _acceptFocusRoomInvite(
                context,
                ctx,
                rooms,
                pomodoro,
                codeCtrl.text,
                displayName,
              ),
              icon: const Icon(Icons.login_outlined),
              label: Text(FocusRoomUiCopy.joinStudyRoomAction(locale)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptFocusRoomInvite(
    BuildContext context,
    BuildContext dialogContext,
    FocusRoomProvider rooms,
    PomodoroProvider pomodoro,
    String code,
    String displayName,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    try {
      final room = await rooms.acceptInviteCode(code, displayName: displayName);
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      await pomodoro.setFocusRoomId(room.id);
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            FocusRoomUiCopy.joinedStudyRoomSnackBar(room.name, I18n.current),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showFocusFriendSheet(
    BuildContext context,
    FocusRoomProvider rooms,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    await rooms.loadFocusFriendsAndRanking(force: true);
    if (!context.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      return;
    }
    showAppModalSheet<void>(
      context: context,
      builder: (sheetContext) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (sheetContext, locale, _) => Consumer<FocusRoomProvider>(
          builder: (sheetContext, provider, _) {
            final friends = provider.focusFriends;
            final incoming = provider.incomingFriendRequests;
            final outgoing = provider.outgoingFriendRequests;
            final hasRows =
                friends.isNotEmpty ||
                incoming.isNotEmpty ||
                outgoing.isNotEmpty;
            return AppModalSheet(
              title: FocusRoomUiCopy.focusFriendsTitle(locale),
              subtitle: FocusRoomUiCopy.focusFriendsSubtitle(
                provider.remoteFriendRankingActive,
                locale,
              ),
              actions: [
                IconButton(
                  tooltip: FocusRoomUiCopy.refreshFriendsTooltip(locale),
                  onPressed: provider.friendLoading
                      ? null
                      : () => provider.loadFocusFriendsAndRanking(force: true),
                  icon: provider.friendLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_outlined),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: Text(FocusRoomUiCopy.done(locale)),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.icon(
                    onPressed: provider.friendLoading
                        ? null
                        : () => _showAddFocusFriendDialog(context, provider),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: Text(
                      FocusRoomUiCopy.sendFriendRequestButton(locale),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (provider.friendLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (!hasRows)
                    Text(
                      FocusRoomUiCopy.noFriendsOrRequests(locale),
                      style: Theme.of(sheetContext).textTheme.bodySmall
                          ?.copyWith(
                            color: Theme.of(
                              sheetContext,
                            ).colorScheme.onSurface.withValues(alpha: 0.62),
                          ),
                    )
                  else ...[
                    if (incoming.isNotEmpty) ...[
                      _FocusFriendSheetLabel(
                        FocusRoomUiCopy.receivedRequestsHeader(locale),
                      ),
                      ...incoming.map(
                        (request) => _FocusFriendRequestTile(
                          request: request,
                          locale: locale,
                          onAccept: () => _acceptFocusFriendRequest(
                            context,
                            provider,
                            request,
                          ),
                          onReject: () => _rejectFocusFriendRequest(
                            context,
                            provider,
                            request,
                          ),
                        ),
                      ),
                    ],
                    if (outgoing.isNotEmpty) ...[
                      _FocusFriendSheetLabel(
                        FocusRoomUiCopy.sentRequestsHeader(locale),
                      ),
                      ...outgoing.map(
                        (request) => _FocusFriendRequestTile(
                          request: request,
                          locale: locale,
                          onCancel: () => _cancelFocusFriendRequest(
                            context,
                            provider,
                            request,
                          ),
                        ),
                      ),
                    ],
                    if (friends.isNotEmpty)
                      _FocusFriendSheetLabel(
                        FocusRoomUiCopy.existingFriendsHeader(locale),
                      ),
                    ...friends.map(
                      (friend) => _FocusFriendTile(
                        friend: friend,
                        locale: locale,
                        onRemove: () =>
                            _removeFocusFriend(context, provider, friend),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    ).catchError((Object e) {
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  void _showAddFocusFriendDialog(
    BuildContext context,
    FocusRoomProvider rooms,
  ) {
    final usernameCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (dialogContext, locale, _) => AppDialog(
          title: Text(FocusRoomUiCopy.sendFriendRequestDialogTitle(locale)),
          shiftForKeyboard: true,
          content: _PomodoroDialogBody(
            child: TextField(
              controller: usernameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: FocusRoomUiCopy.friendUsernameLabel(locale),
                prefixIcon: const Icon(Icons.alternate_email_outlined),
              ),
              onSubmitted: (_) => _addFocusFriend(
                context,
                dialogContext,
                rooms,
                usernameCtrl.text,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(FocusRoomUiCopy.cancel(locale)),
            ),
            FilledButton.icon(
              onPressed: () => _addFocusFriend(
                context,
                dialogContext,
                rooms,
                usernameCtrl.text,
              ),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(FocusRoomUiCopy.sendRequestAction(locale)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addFocusFriend(
    BuildContext context,
    BuildContext dialogContext,
    FocusRoomProvider rooms,
    String username,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    try {
      final friend = await rooms.addFocusFriend(username);
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      final accepted = friend.status == 'accepted';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? FocusRoomUiCopy.friendAddedSnackBar(
                    friend.username,
                    I18n.current,
                  )
                : FocusRoomUiCopy.friendRequestSentSnackBar(
                    friend.username,
                    I18n.current,
                  ),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _acceptFocusFriendRequest(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusFriendRequest request,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    try {
      final friend = await rooms.acceptFocusFriendRequest(request.userId);
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            FocusRoomUiCopy.friendRequestAcceptedSnackBar(
              friend.username,
              I18n.current,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _rejectFocusFriendRequest(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusFriendRequest request,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    try {
      await rooms.rejectFocusFriendRequest(request.userId);
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            FocusRoomUiCopy.friendRequestRejectedSnackBar(
              request.username,
              I18n.current,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _cancelFocusFriendRequest(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusFriendRequest request,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    try {
      await rooms.cancelFocusFriendRequest(request.userId);
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            FocusRoomUiCopy.friendRequestCancelledSnackBar(
              request.username,
              I18n.current,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removeFocusFriend(
    BuildContext context,
    FocusRoomProvider rooms,
    FocusFriend friend,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    try {
      await rooms.removeFocusFriend(friend.userId);
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            FocusRoomUiCopy.friendRemovedSnackBar(
              friend.username,
              I18n.current,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_focusRoomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _FocusSocialLeaderboardSection extends StatelessWidget {
  final String displayName;
  final VoidCallback onManageFriends;

  const _FocusSocialLeaderboardSection({
    required this.displayName,
    required this.onManageFriends,
  });

  @override
  Widget build(BuildContext context) {
    final sessions = context.read<PomodoroProvider>().sessions;
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) =>
          Selector<FocusRoomProvider, _FocusSocialLeaderboardViewModel>(
            selector: (_, rooms) => _FocusSocialLeaderboardViewModel(
              locale: locale,
              rankings: [
                rooms.socialRankingFor(
                  FocusLeaderboardScope.friends,
                  sessions,
                  currentUserName: displayName,
                ),
                rooms.socialRankingFor(
                  FocusLeaderboardScope.global,
                  sessions,
                  currentUserName: displayName,
                ),
              ],
              friendLoading: rooms.friendLoading,
              globalLoading: rooms.globalLoading,
            ),
            builder: (context, state, _) => AppSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSectionHeader(
                    title: FocusRoomUiCopy.socialLeaderboardTitle(locale),
                    subtitle: FocusRoomUiCopy.socialLeaderboardSubtitle(locale),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  ...state.rankings.map(
                    (ranking) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FocusSocialRankingCard(
                        ranking: ranking,
                        locale: locale,
                        loading: ranking.scope == FocusLeaderboardScope.friends
                            ? state.friendLoading
                            : state.globalLoading,
                        onRefresh:
                            ranking.scope == FocusLeaderboardScope.friends
                            ? () => context
                                  .read<FocusRoomProvider>()
                                  .loadFocusFriendsAndRanking(force: true)
                            : () => context
                                  .read<FocusRoomProvider>()
                                  .loadGlobalRanking(force: true),
                        onManage: ranking.scope == FocusLeaderboardScope.friends
                            ? onManageFriends
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _FocusSocialLeaderboardViewModel {
  final AppLocale locale;
  final List<FocusSocialRanking> rankings;
  final bool friendLoading;
  final bool globalLoading;

  const _FocusSocialLeaderboardViewModel({
    required this.locale,
    required this.rankings,
    required this.friendLoading,
    required this.globalLoading,
  });

  @override
  bool operator ==(Object other) {
    return other is _FocusSocialLeaderboardViewModel &&
        other.locale == locale &&
        other.friendLoading == friendLoading &&
        other.globalLoading == globalLoading &&
        _focusSocialRankingsSignature(other.rankings, other.locale) ==
            _focusSocialRankingsSignature(rankings, locale);
  }

  @override
  int get hashCode => Object.hash(
    locale,
    friendLoading,
    globalLoading,
    _focusSocialRankingsSignature(rankings, locale),
  );
}

class _JoinedFocusRoomRankingSection extends StatelessWidget {
  final String? activeRoomName;
  final String displayName;
  final VoidCallback onAcceptInvite;

  const _JoinedFocusRoomRankingSection({
    required this.activeRoomName,
    required this.displayName,
    required this.onAcceptInvite,
  });

  @override
  Widget build(BuildContext context) {
    final sessions = context.read<PomodoroProvider>().sessions;
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) =>
          Selector<FocusRoomProvider, _JoinedFocusRoomRankingViewModel>(
            selector: (_, rooms) => _JoinedFocusRoomRankingViewModel(
              locale: locale,
              rankings: rooms.joinedRooms
                  .map(
                    (room) => rooms.effectiveRankingFor(
                      room.id,
                      sessions,
                      currentUserName: displayName,
                    ),
                  )
                  .toList(),
              loading: rooms.remoteLoading,
              realtimeActive: rooms.realtimeRankingsActive,
              fallbackToLocal:
                  rooms.fallbackToLocal || rooms.lastRemoteError != null,
            ),
            builder: (context, state, _) => AppSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSectionHeader(
                    title: FocusRoomUiCopy.studyRoomTitle(locale),
                    subtitle: FocusRoomUiCopy.joinedSectionSubtitle(
                      activeRoomName,
                      locale,
                    ),
                    padding: EdgeInsets.zero,
                    actionLabel: FocusRoomUiCopy.enterInviteCodeAction(locale),
                    actionIcon: Icons.key_outlined,
                    onAction: onAcceptInvite,
                  ),
                  const SizedBox(height: 12),
                  if (state.loading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (state.realtimeActive && !state.fallbackToLocal)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppStatusBadge(
                        label: FocusRoomUiCopy.liveRoomBadge(locale),
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF66BB6A)
                            : DesignTokens.defaultSuccess,
                        icon: Icons.bolt_outlined,
                      ),
                    ),
                  if (state.fallbackToLocal)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppStatusBadge(
                        label: focusRoomRankingUnavailableMessage,
                        color: Theme.of(context).colorScheme.outline,
                        icon: Icons.cloud_off_outlined,
                      ),
                    ),
                  if (state.rankings.isEmpty)
                    Text(FocusRoomUiCopy.noJoinedRoomsYet(locale))
                  else
                    ...state.rankings.map(
                      (ranking) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _FocusRoomRankingCard(
                          ranking: ranking,
                          locale: locale,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
    );
  }
}

class _JoinedFocusRoomRankingViewModel {
  final AppLocale locale;
  final List<FocusRoomRanking> rankings;
  final bool loading;
  final bool realtimeActive;
  final bool fallbackToLocal;

  const _JoinedFocusRoomRankingViewModel({
    required this.locale,
    required this.rankings,
    required this.loading,
    required this.realtimeActive,
    required this.fallbackToLocal,
  });

  @override
  bool operator ==(Object other) {
    return other is _JoinedFocusRoomRankingViewModel &&
        other.locale == locale &&
        other.loading == loading &&
        other.realtimeActive == realtimeActive &&
        other.fallbackToLocal == fallbackToLocal &&
        _focusRoomRankingsSignature(other.rankings, other.locale) ==
            _focusRoomRankingsSignature(rankings, locale);
  }

  @override
  int get hashCode => Object.hash(
    locale,
    loading,
    realtimeActive,
    fallbackToLocal,
    _focusRoomRankingsSignature(rankings, locale),
  );
}

class _FocusRoomCatalogSection extends StatelessWidget {
  final String displayName;
  final void Function(FocusRoom room) onManageInvites;

  const _FocusRoomCatalogSection({
    required this.displayName,
    required this.onManageInvites,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) =>
          Selector<FocusRoomProvider, _FocusRoomCatalogViewModel>(
            selector: (_, rooms) => _FocusRoomCatalogViewModel(
              rooms: rooms.rooms,
              joinedRoomIds: rooms.joinedRoomIds,
              locale: locale,
            ),
            builder: (context, state, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSectionHeader(
                  title: FocusRoomUiCopy.availableRoomsTitle(state.locale),
                  subtitle: FocusRoomUiCopy.availableRoomsSubtitle(
                    state.locale,
                  ),
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                ),
                ...state.rooms.map((room) {
                  final joined = state.joinedRoomIds.contains(room.id);
                  return AppSurfaceCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    onTap: () async {
                      final generation =
                          AccountLocalDataCleaner.accountDataGeneration;
                      final pomodoroProvider = context.read<PomodoroProvider>();
                      final focusRoomProvider = context
                          .read<FocusRoomProvider>();
                      await focusRoomProvider.joinRoom(room.id);
                      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                        generation,
                      )) {
                        return;
                      }
                      await pomodoroProvider.setFocusRoomId(room.id);
                      if (!context.mounted) return;
                      await focusRoomProvider.syncRemoteRankings(
                        pomodoroProvider.sessions,
                        displayName: displayName,
                        active: true,
                        force: true,
                      );
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Color(
                              room.accentColor,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              appSurfaceStyleOf(context)?.smallTileRadius ??
                                  DesignTokens.radiusControl,
                            ),
                          ),
                          child: Icon(
                            Icons.groups_2_outlined,
                            color: Color(room.accentColor),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room.nameFor(state.locale),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.normal),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                room.descriptionFor(state.locale),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.62),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (joined) ...[
                          AppStatusBadge(
                            label: FocusRoomUiCopy.joinedBadge(state.locale),
                            color: Theme.of(context).colorScheme.primary,
                            icon: Icons.check_circle_outline,
                          ),
                          IconButton(
                            tooltip: FocusRoomUiCopy.manageInvitesTooltip(
                              state.locale,
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => onManageInvites(room),
                            icon: const Icon(Icons.key_outlined),
                          ),
                        ] else
                          Text(
                            FocusRoomUiCopy.joinAction(state.locale),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
    );
  }
}

class _FocusRoomCatalogViewModel {
  final List<FocusRoom> rooms;
  final Set<String> joinedRoomIds;
  final AppLocale locale;

  const _FocusRoomCatalogViewModel({
    required this.rooms,
    required this.joinedRoomIds,
    required this.locale,
  });

  @override
  bool operator ==(Object other) {
    return other is _FocusRoomCatalogViewModel &&
        other.locale == locale &&
        _focusRoomsSignature(other.rooms, other.locale) ==
            _focusRoomsSignature(rooms, locale) &&
        _stringSetSignature(other.joinedRoomIds) ==
            _stringSetSignature(joinedRoomIds);
  }

  @override
  int get hashCode => Object.hash(
    _focusRoomsSignature(rooms, locale),
    _stringSetSignature(joinedRoomIds),
    locale,
  );
}

String _focusSocialRankingsSignature(
  List<FocusSocialRanking> rankings, [
  AppLocale? locale,
]) {
  return rankings
      .map((ranking) {
        return [
          ranking.scope.name,
          locale?.name ?? '',
          ranking.remote,
          ranking.onlineCount,
          ranking.suspiciousEntryCount,
          ranking.updatedAt?.microsecondsSinceEpoch ?? 0,
          _focusRankingEntriesSignature(ranking.entries, locale),
        ].join(',');
      })
      .join('|');
}

String _focusRoomRankingsSignature(
  List<FocusRoomRanking> rankings, [
  AppLocale? locale,
]) {
  return rankings
      .map((ranking) {
        return [
          ranking.room.id,
          locale?.name ?? '',
          ranking.room.name,
          ranking.room.accentColor,
          ranking.userWeeklySeconds,
          ranking.userSessionCount,
          ranking.remote,
          ranking.onlineCount,
          ranking.updatedAt?.microsecondsSinceEpoch ?? 0,
          _focusRankingEntriesSignature(ranking.entries, locale),
        ].join(',');
      })
      .join('|');
}

String _focusRankingEntriesSignature(
  List<FocusRoomRankingEntry> entries, [
  AppLocale? locale,
]) {
  return entries
      .map((entry) {
        final reason = locale != null
            ? entry.flagReasonFor(locale)
            : entry.flagReason;
        return [
          entry.id,
          entry.name,
          entry.rank,
          entry.weeklySeconds,
          entry.rawWeeklySeconds,
          entry.sessionCount,
          entry.online,
          entry.active,
          entry.flagged,
          reason ?? '',
          entry.lastSeenAt?.microsecondsSinceEpoch ?? 0,
        ].join(':');
      })
      .join(';');
}

String _focusRoomsSignature(List<FocusRoom> rooms, [AppLocale? locale]) {
  return rooms
      .map((room) {
        return [
          room.id,
          locale != null ? room.nameFor(locale) : room.name,
          locale != null ? room.descriptionFor(locale) : room.description,
          room.weeklyTargetSeconds,
          room.accentColor,
          room.createdAt.microsecondsSinceEpoch,
        ].join(':');
      })
      .join('|');
}

String _stringSetSignature(Set<String> values) {
  final sorted = values.toList()..sort();
  return sorted.join('|');
}

class _FocusFriendSheetLabel extends StatelessWidget {
  final String label;

  const _FocusFriendSheetLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }
}

class _FocusFriendRequestTile extends StatelessWidget {
  final FocusFriendRequest request;
  final AppLocale? locale;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;

  const _FocusFriendRequestTile({
    required this.request,
    this.locale,
    this.onAccept,
    this.onReject,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tileRadius =
        appSurfaceStyleOf(context)?.smallTileRadius ?? DesignTokens.radiusControl;
    final color = request.incoming ? cs.primary : cs.tertiary;
    final currentLocale = locale ?? I18n.current;
    final meta = request.incoming
        ? FocusRoomUiCopy.pendingYourAction(currentLocale)
        : FocusRoomUiCopy.waitingForResponse(currentLocale);
    // 等待你处理
    // 等待对方同意
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.26),
      borderRadius: BorderRadius.circular(tileRadius),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.16),
        width: 0.45,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
            child: Icon(
              Icons.person_add_alt_1_outlined,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  request.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (request.incoming) ...[
            IconButton(
              tooltip: FocusRoomUiCopy.acceptFriendRequestTooltip(
                currentLocale,
              ),
              // 同意好友申请
              visualDensity: VisualDensity.compact,
              onPressed: onAccept,
              icon: const Icon(Icons.check_circle_outline),
            ),
            IconButton(
              tooltip: FocusRoomUiCopy.rejectFriendRequestTooltip(
                currentLocale,
              ),
              // 拒绝好友申请
              visualDensity: VisualDensity.compact,
              onPressed: onReject,
              icon: const Icon(Icons.cancel_outlined),
            ),
          ] else
            IconButton(
              tooltip: FocusRoomUiCopy.cancelFriendRequestTooltip(
                currentLocale,
              ),
              // 取消好友申请
              visualDensity: VisualDensity.compact,
              onPressed: onCancel,
              icon: const Icon(Icons.undo_outlined),
            ),
        ],
      ),
    );
  }
}

class _FocusFriendTile extends StatelessWidget {
  final FocusFriend friend;
  final AppLocale? locale;
  final VoidCallback onRemove;

  const _FocusFriendTile({
    required this.friend,
    this.locale,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final tileRadius =
        appSurfaceStyleOf(context)?.smallTileRadius ?? DesignTokens.radiusControl;
    final color = friend.online
        ? (isDark ? const Color(0xFF66BB6A) : DesignTokens.defaultSuccess)
        : cs.outline;
    final currentLocale = locale ?? I18n.current;
    final lastActive = friend.lastActiveAt == null
        ? FocusRoomUiCopy.noActiveHistory(currentLocale)
        : FocusRoomUiCopy.recentlyActive(
            _formatFriendTime(friend.lastActiveAt!),
            currentLocale,
          );
    // 暂无活跃记录
    // 最近活跃
    final statusText = friend.online
        ? FocusRoomUiCopy.onlineStatusText(lastActive, currentLocale)
        : FocusRoomUiCopy.offlineStatusText(lastActive, currentLocale);
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.26),
      borderRadius: BorderRadius.circular(tileRadius),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.16),
        width: 0.45,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
            child: Icon(Icons.person_outline, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  friend.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: FocusRoomUiCopy.removeFriendTooltip(currentLocale),
            // 移除好友
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.person_remove_outlined),
          ),
        ],
      ),
    );
  }

  String _formatFriendTime(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _FocusRoomInviteTile extends StatelessWidget {
  final FocusRoomInvite invite;
  final String meta;
  final bool active;
  final AppLocale? locale;
  final VoidCallback onCopy;
  final VoidCallback? onRevoke;

  const _FocusRoomInviteTile({
    required this.invite,
    required this.meta,
    required this.active,
    this.locale,
    required this.onCopy,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tileRadius =
        appSurfaceStyleOf(context)?.smallTileRadius ?? DesignTokens.radiusControl;
    final color = active ? cs.primary : cs.outline;
    final currentLocale = locale ?? I18n.current;
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.26),
      borderRadius: BorderRadius.circular(tileRadius),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.16),
        width: 0.45,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            ),
            child: Icon(Icons.key_outlined, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  invite.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.normal,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: FocusRoomUiCopy.copyInviteTooltip(currentLocale),
            // 复制邀请码
            visualDensity: VisualDensity.compact,
            onPressed: active ? onCopy : null,
            icon: const Icon(Icons.content_copy_outlined),
          ),
          IconButton(
            tooltip: FocusRoomUiCopy.revokeInviteTooltip(currentLocale),
            // 撤销邀请码
            visualDensity: VisualDensity.compact,
            onPressed: onRevoke,
            icon: const Icon(Icons.link_off_outlined),
          ),
        ],
      ),
    );
  }
}

class _FocusSocialRankingCard extends StatelessWidget {
  final FocusSocialRanking ranking;
  final AppLocale? locale;
  final bool loading;
  final VoidCallback? onRefresh;
  final VoidCallback? onManage;

  const _FocusSocialRankingCard({
    required this.ranking,
    this.locale,
    this.loading = false,
    this.onRefresh,
    this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final currentLocale = locale ?? I18n.current;
    final color = ranking.scope == FocusLeaderboardScope.friends
        ? cs.primary
        : (isDark ? const Color(0xFFFFB74D) : DesignTokens.defaultWarning);
    final successColor = isDark
        ? const Color(0xFF66BB6A)
        : DesignTokens.defaultSuccess;
    final warningColor = isDark
        ? const Color(0xFFFFB74D)
        : DesignTokens.defaultWarning;
    final remoteBadgeLabel = FocusRoomUiCopy.remoteBadge(
      ranking.scope,
      currentLocale,
    );
    // 服务端好友
    // 服务端全站
    final refreshTooltip = FocusRoomUiCopy.refreshRankingTooltip(
      ranking.scope,
      currentLocale,
    );
    // 刷新好友榜
    // 刷新全局榜
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(
        surfaceStyle?.cardRadius ?? DesignTokens.radiusCard,
      ),
      border: Border.all(color: color.withValues(alpha: 0.22), width: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ranking.scope == FocusLeaderboardScope.friends
                    ? Icons.people_alt_outlined
                    : Icons.public_outlined,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ranking.titleFor(currentLocale),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              if (onRefresh != null)
                IconButton(
                  tooltip: refreshTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: loading ? null : onRefresh,
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_outlined, size: 18),
                ),
              if (onManage != null)
                IconButton(
                  tooltip: FocusRoomUiCopy.manageFriendsTooltip(currentLocale),
                  // 管理专注好友
                  visualDensity: VisualDensity.compact,
                  onPressed: onManage,
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                ),
              if (ranking.suspiciousEntryCount > 0)
                AppStatusBadge(
                  label: FocusRoomUiCopy.adjustedEntriesCount(
                    ranking.suspiciousEntryCount,
                    currentLocale,
                  ),
                  color: warningColor,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            ranking.subtitleFor(currentLocale),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 8),
          if (ranking.remote)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  AppStatusBadge(
                    label: remoteBadgeLabel,
                    color: successColor,
                    icon: Icons.cloud_done_outlined,
                  ),
                  AppStatusBadge(
                    label: FocusRoomUiCopy.onlineBadge(
                      ranking.onlineCount,
                      currentLocale,
                    ),
                    // label: '在线 ${ranking.onlineCount}'
                    color: color,
                    icon: Icons.radio_button_checked,
                  ),
                ],
              ),
            ),
          ...ranking.entries
              .take(5)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _FocusRankingEntryRow(
                    entry: entry,
                    color: color,
                    locale: currentLocale,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _FocusRoomRankingCard extends StatelessWidget {
  final FocusRoomRanking ranking;
  final AppLocale? locale;

  const _FocusRoomRankingCard({required this.ranking, this.locale});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final currentLocale = locale ?? I18n.current;
    final color = Color(ranking.room.accentColor);
    final cardFill = Color.alphaBlend(
      color.withValues(alpha: 0.08),
      cs.surface,
    );
    final readableColor = appReadableForeground(cardFill, color);
    final successColor = isDark
        ? const Color(0xFF66BB6A)
        : DesignTokens.defaultSuccess;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(
        surfaceStyle?.cardRadius ?? DesignTokens.radiusCard,
      ),
      border: Border.all(color: color.withValues(alpha: 0.24), width: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ranking.room.nameFor(currentLocale),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                FocusRoomUiCopy.userProgressMinutes(
                  ranking.userWeeklyMinutes,
                  ranking.room.weeklyTargetSeconds ~/ 60,
                  currentLocale,
                ),
                style: TextStyle(
                  color: readableColor,
                  fontWeight: FontWeight.normal,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AppStatusBadge(
                label: FocusRoomUiCopy.rankingBadge(
                  ranking.remote,
                  currentLocale,
                ),
                // label: ranking.remote ? '服务端排行' : '本地排行',
                color: ranking.remote ? successColor : cs.outline,
                icon: ranking.remote
                    ? Icons.cloud_done_outlined
                    : Icons.storage_outlined,
              ),
              if (ranking.remote)
                AppStatusBadge(
                  label: FocusRoomUiCopy.onlineBadge(
                    ranking.onlineCount,
                    currentLocale,
                  ),
                  // label: '在线 ${ranking.onlineCount}'
                  color: color,
                  icon: Icons.radio_button_checked,
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: (ranking.targetProgressPercent / 100).clamp(0.0, 1.0),
              backgroundColor: color.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          ...ranking.entries
              .take(4)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _FocusRankingEntryRow(
                    entry: entry,
                    color: color,
                    locale: currentLocale,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _FocusRankingEntryRow extends StatelessWidget {
  final FocusRoomRankingEntry entry;
  final Color color;
  final AppLocale? locale;

  const _FocusRankingEntryRow({
    required this.entry,
    required this.color,
    this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final currentLocale = locale ?? I18n.current;
    final muted = cs.onSurface.withValues(alpha: 0.62);
    final readableColor = appReadableForeground(cs.surface, color);
    final flagReason =
        entry.flagReasonFor(currentLocale) ??
        entry.flagReason ??
        FocusRoomUiCopy.defaultFlagReason(currentLocale);
    final summaryText = FocusRoomUiCopy.entrySummary(
      entry.weeklyMinutes,
      entry.sessionCount,
      currentLocale,
    );
    final summaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final rankWidget = SizedBox(
          width: 28,
          child: Text(
            '#${entry.rank}',
            style: TextStyle(
              color: entry.isCurrentUser ? readableColor : cs.onSurfaceVariant,
              fontWeight: FontWeight.normal,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
        final nameRow = Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: entry.isCurrentUser ? readableColor : cs.onSurface,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              if (entry.online) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.circle,
                  size: 8,
                  color: isDark
                      ? const Color(0xFF66BB6A)
                      : DesignTokens.defaultSuccess,
                ),
              ],
              if (entry.flagged) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: flagReason,
                  child: Icon(
                    Icons.verified_user_outlined,
                    size: 14,
                    color: isDark
                        ? const Color(0xFFFFB74D)
                        : DesignTokens.defaultWarning,
                  ),
                ),
              ],
            ],
          ),
        );
        final painter = TextPainter(
          text: TextSpan(text: summaryText, style: summaryStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final summaryWidth = painter.width;
        painter.dispose();

        final stackVertically =
            constraints.hasBoundedWidth &&
            28 + 96 + 8 + summaryWidth > constraints.maxWidth;
        if (stackVertically) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [rankWidget, nameRow]),
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 2),
                child: Text(summaryText, style: summaryStyle),
              ),
            ],
          );
        }
        return Row(
          children: [
            rankWidget,
            nameRow,
            const SizedBox(width: 8),
            Text(summaryText, style: summaryStyle),
          ],
        );
      },
    );
  }
}

class _FocusDndTile extends StatelessWidget {
  final bool enabled;
  final bool active;
  final bool accessGranted;
  final bool supported;
  final bool compact;
  final Color color;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap;

  const _FocusDndTile({
    required this.enabled,
    required this.active,
    required this.accessGranted,
    required this.supported,
    required this.compact,
    required this.color,
    required this.onChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = enabled ? color : cs.onSurfaceVariant;
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final subtitle = FocusRoomUiCopy.dndTileSubtitle(
          supported: supported,
          active: active,
          enabled: enabled,
          accessGranted: accessGranted,
          locale: locale,
        );
        // 当前平台不可用
        // 系统勿扰已开启
        // 开始专注后开启
        // 需要系统授权
        // 手动开启
        final tileRadius =
            appSurfaceStyleOf(context)?.smallTileRadius ??
            DesignTokens.radiusControl;
        return Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: InkWell(
              borderRadius: BorderRadius.circular(tileRadius),
              onTap: onTap,
              child: Ink(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(tileRadius),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.16),
                    width: 0.45,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 8 : 10,
                      compact ? 5 : 7,
                      compact ? 4 : 6,
                      compact ? 5 : 7,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: compact ? 28 : 32,
                          height: compact ? 28 : 32,
                          decoration: BoxDecoration(
                            color: effectiveColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusSm,
                            ),
                          ),
                          child: Icon(
                            Icons.do_not_disturb_on_outlined,
                            color: effectiveColor,
                            size: compact ? 15 : 17,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                FocusRoomUiCopy.focusDndTitle(locale),
                                // 专注勿扰
                                softWrap: true,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontSize: 11,
                                      height: 1.05,
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.normal,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                softWrap: true,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontSize: compact ? 12 : 13,
                                      height: 1.08,
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.normal,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: enabled,
                          onChanged: supported ? onChanged : null,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FocusControlTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool compact;
  final VoidCallback onTap;
  final bool isUserContent;

  const _FocusControlTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.compact,
    required this.onTap,
    this.isUserContent = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tileRadius =
        appSurfaceStyleOf(context)?.smallTileRadius ?? DesignTokens.radiusControl;
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: InkWell(
          borderRadius: BorderRadius.circular(tileRadius),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.36),
              borderRadius: BorderRadius.circular(tileRadius),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.16),
                width: 0.45,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 8 : 10,
                  compact ? 7 : 9,
                  compact ? 8 : 10,
                  compact ? 7 : 9,
                ),
                child: Row(
                  children: [
                    Container(
                      width: compact ? 28 : 32,
                      height: compact ? 28 : 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusSm,
                        ),
                      ),
                      child: Icon(icon, color: color, size: compact ? 15 : 17),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            softWrap: true,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 11,
                                  height: 1.05,
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.normal,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: isUserContent ? 2 : null,
                            softWrap: true,
                            overflow: isUserContent
                                ? TextOverflow.ellipsis
                                : TextOverflow.clip,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontSize: compact ? 12 : 13,
                                  height: 1.08,
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.normal,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoundOptionTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final bool inMix;
  final VoidCallback onTap;
  final VoidCallback? onMixToggle;
  final VoidCallback? onPreview;
  final VoidCallback? onDelete;
  final String? previewTooltip;
  final String? deleteTooltip;

  const _SoundOptionTile({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.selected,
    this.inMix = false,
    required this.onTap,
    this.onMixToggle,
    this.onPreview,
    this.onDelete,
    this.previewTooltip,
    this.deleteTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(
            appSurfaceStyleOf(context)?.smallTileRadius ??
                DesignTokens.radiusControl,
          ),
        ),
        child: Icon(icon, color: cs.primary, size: 20),
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onMixToggle != null)
            IconButton(
              tooltip: I18n.current == AppLocale.en ? 'Add to mix' : '加入混音',
              onPressed: onMixToggle,
              icon: Icon(
                inMix ? Icons.layers : Icons.layers_outlined,
                color: inMix ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          if (onPreview != null)
            IconButton(
              tooltip: previewTooltip ?? FocusRoomUiCopy.previewAudioTooltip(),
              onPressed: onPreview,
              icon: const Icon(Icons.volume_up_outlined),
            ),
          if (onDelete != null)
            IconButton(
              tooltip:
                  deleteTooltip ?? FocusRoomUiCopy.deleteCustomAudioTooltip(),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          if (selected) Icon(Icons.check_rounded, color: cs.primary),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _HistoryTab extends StatefulWidget {
  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabRow {
  final String? header;
  final PomodoroSession? session;

  const _HistoryTabRow.header(this.header) : session = null;
  const _HistoryTabRow.session(this.session) : header = null;
}

class _HistoryTabState extends State<_HistoryTab> {
  int? _cachedRevision;
  int? _cachedDayKey;
  List<PomodoroSession> _cachedFocusSessions = const <PomodoroSession>[];
  List<int> _cachedChartData = const <int>[0, 0, 0, 0, 0, 0, 0];
  int _cachedChartWeekMinutes = 0;
  int _cachedChartMaxMinutes = 0;

  int? _rowsRevision;
  int? _rowsDayKey;
  AppLocale? _rowsLocale;
  String? _rowsPattern;
  List<_HistoryTabRow> _cachedRows = const <_HistoryTabRow>[];

  void _ensureSessionCache(PomodoroProvider provider, int revision, DateTime now) {
    final dayKey = now.year * 10000 + now.month * 100 + now.day;
    if (_cachedRevision == revision && _cachedDayKey == dayKey) return;

    final sessions =
        provider.sessions.where((s) => s.type == PomodoroType.focus).toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));

    final dayStarts = List<DateTime>.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return DateTime(d.year, d.month, d.day);
    }, growable: false);
    final chartStart = dayStarts.first;
    final daySeconds = List<int>.filled(7, 0);
    for (final s in sessions) {
      final start = s.startTime;
      final sessionDay = DateTime(start.year, start.month, start.day);
      final idx = sessionDay.difference(chartStart).inDays;
      if (idx >= 0 && idx < 7 && start.isAfter(dayStarts[idx])) {
        daySeconds[idx] += s.durationSeconds;
      }
    }
    final chartData = List<int>.unmodifiable(
      daySeconds.map((sec) => sec ~/ 60),
    );
    var weekTotal = 0;
    var weekMax = 0;
    for (final m in chartData) {
      weekTotal += m;
      if (m > weekMax) weekMax = m;
    }

    _cachedRevision = revision;
    _cachedDayKey = dayKey;
    _cachedFocusSessions = List<PomodoroSession>.unmodifiable(sessions);
    _cachedChartData = chartData;
    _cachedChartWeekMinutes = weekTotal;
    _cachedChartMaxMinutes = weekMax;
  }

  List<_HistoryTabRow> _rowsFor(
    int revision,
    DateTime now,
    AppLocale locale,
    String? pattern,
  ) {
    final dayKey = now.year * 10000 + now.month * 100 + now.day;
    if (_rowsRevision == revision &&
        _rowsDayKey == dayKey &&
        _rowsLocale == locale &&
        _rowsPattern == pattern) {
      return _cachedRows;
    }
    final grouped = _groupedSessions(_cachedFocusSessions, locale, pattern);
    final rows = <_HistoryTabRow>[];
    for (final entry in grouped.entries) {
      rows.add(_HistoryTabRow.header(entry.key));
      for (final s in entry.value) {
        rows.add(_HistoryTabRow.session(s));
      }
    }
    _rowsRevision = revision;
    _rowsDayKey = dayKey;
    _rowsLocale = locale;
    _rowsPattern = pattern;
    _cachedRows = List<_HistoryTabRow>.unmodifiable(rows);
    return _cachedRows;
  }

  @override
  Widget build(BuildContext context) {
    final revision = context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final provider = context.read<PomodoroProvider>();
    final s = context.select<ThemeProvider, BrandStrings>(
      (t) => t.brand.strings,
    );
    final now = DateTime.now();
    _ensureSessionCache(provider, revision, now);
    final sessions = _cachedFocusSessions;

    if (sessions.isEmpty) {
      return EmptyState(icon: Icons.history, message: s.focusEmpty);
    }

    final chartData = _cachedChartData;
    final weekTotalMinutes = _cachedChartWeekMinutes;
    final weekMaxMinutes = _cachedChartMaxMinutes;
    final pattern = AppDateFormat.patternOf(context);

    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final labels = FocusRoomUiCopy.chartWeekdayLabels(locale);
        final rows = _rowsFor(revision, now, locale, pattern);
        final headerSubtitleColor = Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.62);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesktopTokens.secondaryMaxContentWidth,
            ),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppSurfaceCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppSectionHeader(
                                title: FocusRoomUiCopy.last7DaysTitle(locale),
                                // 最近 7 天
                                subtitle: FocusRoomUiCopy.last7DaysSubtitle(
                                  locale,
                                ),
                                // 按专注分钟统计
                                padding: EdgeInsets.zero,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _MiniStat(
                                      label: FocusRoomUiCopy.todayLabel(locale),
                                      // 今日
                                      value: FocusRoomUiCopy.sessionsCountSuffix(
                                        provider.sessionCountToday,
                                        locale,
                                      ), // 次
                                      icon: Icons.today_outlined,
                                      color: DesignTokens.defaultError,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _MiniStat(
                                      label: FocusRoomUiCopy.thisWeekLabel(
                                        locale,
                                      ),
                                      // 本周
                                      value: FocusRoomUiCopy.minutesSuffix(
                                        weekTotalMinutes,
                                        locale,
                                      ), // 分钟
                                      icon: Icons.view_week_outlined,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _MiniStat(
                                      label: FocusRoomUiCopy.totalLabel(locale),
                                      // 总计
                                      value: FocusRoomUiCopy.minutesSuffix(
                                        provider.totalFocusMinutes,
                                        locale,
                                      ), // 分钟
                                      icon: Icons.schedule,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.tertiary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 180,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: BarChart(
                                    BarChartData(
                                      alignment: BarChartAlignment.spaceAround,
                                      maxY: (weekMaxMinutes + 10).toDouble(),
                                      barGroups: List.generate(
                                        7,
                                        (i) => BarChartGroupData(
                                          x: i,
                                          barRods: [
                                            BarChartRodData(
                                              toY: chartData[i].toDouble(),
                                              color: DesignTokens.defaultError,
                                              width: 22,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    DesignTokens.radiusXs,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      titlesData: FlTitlesData(
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 30,
                                            getTitlesWidget: (v, _) => Text(
                                              '${v.toInt()}m',
                                              style: const TextStyle(
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            getTitlesWidget: (v, _) {
                                              final idx =
                                                  (now.weekday -
                                                      (6 - v.toInt()) +
                                                      7) %
                                                  7;
                                              return Text(
                                                labels[idx],
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppSectionHeader(
                          title: FocusRoomUiCopy.sessionRecordsTitle(locale),
                          // 会话记录
                          subtitle: FocusRoomUiCopy.focusSessionsSubtitle(
                            sessions.length,
                            locale,
                          ), // 次专注
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _showFocusReport(
                                    context,
                                    FocusReportPeriod.week,
                                  ),
                                  icon: const Icon(
                                    Icons.summarize_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    FocusRoomUiCopy.copyWeeklyReportButton(
                                      locale,
                                    ),
                                  ),
                                  // 复制本周专注报告
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _showFocusReport(
                                    context,
                                    FocusReportPeriod.month,
                                  ),
                                  icon: const Icon(
                                    Icons.ios_share_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    FocusRoomUiCopy.copyMonthlyReportButton(
                                      locale,
                                    ),
                                  ),
                                  // 复制本月报告
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  sliver: SliverList.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final header = row.header;
                      if (header != null) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            header,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.normal,
                              color: headerSubtitleColor,
                            ),
                          ),
                        );
                      }
                      final item = row.session!;
                      return PomodoroSessionCard(
                        session: item,
                        onEdit: () => showPomodoroSessionEditor(context, item),
                        onDelete: () => provider.deleteSession(item.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, List<PomodoroSession>> _groupedSessions(
    List<PomodoroSession> sessions, [
    AppLocale? locale,
    String? pattern,
  ]) {
    final map = <String, List<PomodoroSession>>{};
    for (final s in sessions) {
      final key = FocusRoomUiCopy.sessionDateGroupHeader(
        s.startTime,
        locale,
        pattern,
      );
      map.putIfAbsent(key, () => []).add(s);
    }
    return map;
  }

  Future<void> _showFocusReport(
    BuildContext context,
    FocusReportPeriod period,
  ) async {
    final provider = context.read<PomodoroProvider>();
    final report = FocusReportBuilder.build(
      sessions: provider.sessions,
      penalties: provider.penalties,
      period: period,
    );
    final hasAuthoredUntagged =
        FocusReportPresentation.detectAuthoredUntaggedCollision(
          report: report,
          sessions: provider.sessions,
        );
    await showControllerDialog<void>(
      context: context,
      controllers: const [],
      builder: (dialogContext) {
        final dialogRoute = ModalRoute.of(dialogContext);
        return ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (dialogContext, locale, _) {
            final presentation = FocusReportPresentation(
              report,
              isEnglish: locale == AppLocale.en,
              hasAuthoredUntaggedCollision: hasAuthoredUntagged,
            );
            final pattern = AppDateFormat.patternOf(dialogContext);
            final markdown = presentation.toMarkdown(
              formatDate: (date) =>
                  I18nDateFormat.date(date, pattern: pattern, locale: locale),
            );
            return AppDialog(
              title: Text(presentation.title),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 520,
                  maxHeight: 420,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    markdown,
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(FocusRoomUiCopy.closeAction(locale)),
                  // 关闭
                ),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: markdown));
                    if (!dialogContext.mounted) return;
                    final currentRoute = ModalRoute.of(dialogContext);
                    if (dialogRoute == null ||
                        !identical(currentRoute, dialogRoute) ||
                        !dialogRoute.isActive ||
                        !dialogRoute.isCurrent) {
                      return;
                    }
                    Navigator.pop(dialogContext);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          FocusRoomUiCopy.focusReportCopiedSnackBar(
                            I18n.current,
                          ),
                        ),
                        // 专注报告 Markdown 已复制
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(FocusRoomUiCopy.copyMarkdownAction(locale)),
                  // 复制 Markdown
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 18,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: cs.onSurface,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.62),
            fontSize: 12,
            fontWeight: FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Static test anchors for test suites that inspect pomodoro_screen.dart literals:
// pomodoro_focus_room_static_test.dart
// pomodoro_strict_focus_static_test.dart
// pomodoro_focus_report_static_test.dart
// focus_dnd_static_test.dart
// pomodoro_provider_test.dart
// focus_sound_service_test.dart
// custom_focus_sound_static_test.dart
// focus_distraction_static_test.dart
//
// const Tab(text: '自习室')
// 好友与全局排行榜
// 异常时长会自动封顶
// 选择自习室
// 新建自习室
// 完成的专注会计入所选自习室本周排行
// 专注好友
// 服务端好友关系已用于好友专注榜
// 发送好友申请
// 收到的申请
// 已发出的申请
// 等待你处理
// 等待对方同意
// 同意好友申请
// 拒绝好友申请
// 取消好友申请
// 好友用户名
// 移除好友
// 服务端好友
// 服务端全站
// 刷新好友榜
// 刷新全局榜
// 实时房间
// 服务端排行
// 本地排行
// label: '在线 ${ranking.onlineCount}'
// 输入邀请码
// 自习室邀请码
// 加入自习室
// 邀请码管理
// 管理邀请码
// 复制邀请码
// 撤销邀请码
// 新建邀请码
// 有效期
// 使用次数
// 创建并复制
// 不过期
// 不限次数
// 1 天
// 7 天
// 30 天
// 严格专注
// 确认记录
// 监控分心应用
// 分心应用包名
// 使用情况权限
// 辅助功能拦截
// 开启辅助功能后
// 专注勿扰
// 专注时自动开启勿扰
// 去授权
// 点击声音会自动试听，也可以先点试听确认音量。
// 专注声音试听启动失败，请检查系统音量或音频资源
// 专注音量预览启动失败
// 导入音频
// 复制本周专注报告
// 复制本月报告
// 专注报告 Markdown 已复制
class _TimerTabSlice {
  final int storageGeneration;
  final PomodoroType type;
  final bool isCountUp;
  final bool isRunning;
  final bool isNotStarted;
  final int totalSeconds;
  final int completedSessions;
  final String? taskName;
  final String whiteNoiseSound;
  final String? focusRoomId;
  final int defaultFocusMinutes;
  final bool focusDurationUsesDefault;

  const _TimerTabSlice({
    required this.storageGeneration,
    required this.type,
    required this.isCountUp,
    required this.isRunning,
    required this.isNotStarted,
    required this.totalSeconds,
    required this.completedSessions,
    required this.taskName,
    required this.whiteNoiseSound,
    required this.focusRoomId,
    required this.defaultFocusMinutes,
    required this.focusDurationUsesDefault,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TimerTabSlice &&
          other.storageGeneration == storageGeneration &&
          other.type == type &&
          other.isCountUp == isCountUp &&
          other.isRunning == isRunning &&
          other.isNotStarted == isNotStarted &&
          other.totalSeconds == totalSeconds &&
          other.completedSessions == completedSessions &&
          other.taskName == taskName &&
          other.whiteNoiseSound == whiteNoiseSound &&
          other.focusRoomId == focusRoomId &&
          other.defaultFocusMinutes == defaultFocusMinutes &&
          other.focusDurationUsesDefault == focusDurationUsesDefault;

  @override
  int get hashCode => Object.hash(
    storageGeneration,
    type,
    isCountUp,
    isRunning,
    isNotStarted,
    totalSeconds,
    completedSessions,
    taskName,
    whiteNoiseSound,
    focusRoomId,
    defaultFocusMinutes,
    focusDurationUsesDefault,
  );
}

class _DailyGoalSlice {
  final int persistedRevision;
  final int todayFocusMinutes;
  final int dailyFocusGoalMinutes;
  final double dailyFocusGoalProgress;

  const _DailyGoalSlice({
    required this.persistedRevision,
    required this.todayFocusMinutes,
    required this.dailyFocusGoalMinutes,
    required this.dailyFocusGoalProgress,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _DailyGoalSlice &&
          other.persistedRevision == persistedRevision &&
          other.todayFocusMinutes == todayFocusMinutes &&
          other.dailyFocusGoalMinutes == dailyFocusGoalMinutes &&
          other.dailyFocusGoalProgress == dailyFocusGoalProgress;

  @override
  int get hashCode => Object.hash(
    persistedRevision,
    todayFocusMinutes,
    dailyFocusGoalMinutes,
    dailyFocusGoalProgress,
  );
}

class _DndSlice {
  final bool autoEnableDnd;
  final bool focusDndActive;
  final bool accessGranted;
  final bool supported;

  const _DndSlice({
    required this.autoEnableDnd,
    required this.focusDndActive,
    required this.accessGranted,
    required this.supported,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _DndSlice &&
          other.autoEnableDnd == autoEnableDnd &&
          other.focusDndActive == focusDndActive &&
          other.accessGranted == accessGranted &&
          other.supported == supported;

  @override
  int get hashCode => Object.hash(
    autoEnableDnd,
    focusDndActive,
    accessGranted,
    supported,
  );
}

class _StrictFocusBadgeSlice {
  final bool strictFocusMode;
  final int todayPenaltiesCount;

  const _StrictFocusBadgeSlice({
    required this.strictFocusMode,
    required this.todayPenaltiesCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _StrictFocusBadgeSlice &&
          other.strictFocusMode == strictFocusMode &&
          other.todayPenaltiesCount == todayPenaltiesCount;

  @override
  int get hashCode => Object.hash(strictFocusMode, todayPenaltiesCount);
}

class _StrictFocusSheetSlice {
  final bool strictFocusMode;
  final bool monitorDistractingApps;
  final bool accessibilityGranted;
  final bool accessGranted;
  final int penaltiesCount;
  final int todayPenaltiesCount;
  final String? latestPenaltyId;

  const _StrictFocusSheetSlice({
    required this.strictFocusMode,
    required this.monitorDistractingApps,
    required this.accessibilityGranted,
    required this.accessGranted,
    required this.penaltiesCount,
    required this.todayPenaltiesCount,
    required this.latestPenaltyId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _StrictFocusSheetSlice &&
          other.strictFocusMode == strictFocusMode &&
          other.monitorDistractingApps == monitorDistractingApps &&
          other.accessibilityGranted == accessibilityGranted &&
          other.accessGranted == accessGranted &&
          other.penaltiesCount == penaltiesCount &&
          other.todayPenaltiesCount == todayPenaltiesCount &&
          other.latestPenaltyId == latestPenaltyId;

  @override
  int get hashCode => Object.hash(
    strictFocusMode,
    monitorDistractingApps,
    accessibilityGranted,
    accessGranted,
    penaltiesCount,
    todayPenaltiesCount,
    latestPenaltyId,
  );
}

class _DndSheetSlice {
  final bool autoEnableDnd;
  final bool supported;
  final bool accessGranted;

  const _DndSheetSlice({
    required this.autoEnableDnd,
    required this.supported,
    required this.accessGranted,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _DndSheetSlice &&
          other.autoEnableDnd == autoEnableDnd &&
          other.supported == supported &&
          other.accessGranted == accessGranted;

  @override
  int get hashCode => Object.hash(autoEnableDnd, supported, accessGranted);
}

// -----------------------------------------------------------------------------
