import '../widgets/app_date_format.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/account_preference_writes.dart';
import '../core/design_tokens.dart';
import '../core/focus_sound_catalog.dart';
import '../core/goal_icons.dart';
import '../core/goal_validation.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../desktop_web/desktop_embedded_scope.dart';
import '../models/goal.dart';
import '../models/recurrence.dart';
import '../models/workspace.dart';
import '../providers/custom_focus_sound_provider.dart';
import '../providers/notification_service.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/share_provider.dart';
import '../services/alarm_service.dart';
import '../services/focus_sound_service.dart';
import '../services/goal_editor_origin.dart';
import '../services/recurrence_engine.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/brand_background.dart';
import '../widgets/recurrence_picker.dart';
import '../widgets/reminder_health_hint.dart';
import '../widgets/reminder_plan_editor.dart';
import '../widgets/surface_components.dart';

const List<int> _presetColors = <int>[
  0xFFFFA726,
  0xFF66BB6A,
  0xFF42A5F5,
  0xFFAB47BC,
  0xFFEF5350,
  0xFF26A69A,
];

const List<int> _focusMinutePresets = <int>[15, 25, 30, 45, 60, 90];

class GoalEditScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final GoalItem? goal;
  const GoalEditScreen({super.key, this.goal});

  @override
  State<GoalEditScreen> createState() => _GoalEditScreenState();
}

class _GoalEditScreenState extends State<GoalEditScreen> {
  // ---- Basic ----
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  DateTime? _startDate;
  DateTime? _targetDate;
  GoalStatus _status = GoalStatus.active;
  int _colorValue = 0xFFFFA726;
  late String _iconName;

  // ---- Recurrence ----
  RecurrenceRule _recurrence = const RecurrenceRule();

  // ---- Scheduling ----
  GoalScheduling _scheduling = const GoalScheduling.fixed();
  late final TextEditingController _minGapCtrl;
  late final TextEditingController _maxPerWeekCtrl;
  late final TextEditingController _maxPerMonthCtrl;

  // ---- Skip holidays ----
  bool _skipHolidays = false;

  // ---- Focus ----
  FocusLink _focus = const FocusLink.disabled();
  late final TextEditingController _focusMinutesCtrl;

  // ---- Reminder ----
  ReminderConfig _reminder = const ReminderConfig.disabled();
  ReminderPlan _reminderPlan = const ReminderPlan.disabled();

  // ---- Time target ----
  late final TextEditingController _timeTargetCtrl;

  // ---- Daily count ----
  late final TextEditingController _dailyCountCtrl;

  // ---- Milestones & auto progress ----
  bool _autoProgress = true;
  double _manualProgress = 0;
  List<GoalMilestone> _milestones = <GoalMilestone>[];
  late final TextEditingController _milestoneCtrl;

  /// 若为编辑模式则为原始 id；为新建模式时首次保存后赋值，
  /// 这样后续模块保存可直接走 `GoalProvider.update`。
  String? _editingId;

  /// 保留 createdAt，避免新建后再次 update 时时间被刷新。
  DateTime? _createdAt;
  String _workspaceId = 'private';

  bool _persisting = false;
  GoalEditorOrigin? _origin;
  String? _acknowledgedDraft;

  bool get _isExisting => _editingId != null;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
    final g = widget.goal == null
        ? null
        : GoalItem.fromJson(jsonDecode(jsonEncode(widget.goal!.toJson())));
    _editingId = g?.id;
    _createdAt = g?.createdAt;
    _workspaceId = _normalizeWorkspaceId(g?.workspaceId);

    _titleCtrl = TextEditingController(text: g?.title ?? '');
    _descCtrl = TextEditingController(text: g?.description ?? '');
    _startDate = g?.startDate;
    _targetDate = g?.targetDate;
    _status = g?.status ?? GoalStatus.active;
    _colorValue = g?.colorValue ?? 0xFFFFA726;
    _iconName = g?.icon ?? 'flag';
    _recurrence = g?.recurrence ?? const RecurrenceRule();
    _scheduling = g?.scheduling ?? const GoalScheduling.fixed();
    _skipHolidays = g?.skipHolidays ?? false;
    _focus = g?.focusLink ?? const FocusLink.disabled();
    _reminder = g?.reminder ?? const ReminderConfig.disabled();
    _reminderPlan = g?.reminderPlan ?? ReminderPlan.fromLegacy(_reminder);
    _autoProgress = g?.autoProgress ?? true;
    _manualProgress = g?.autoProgress == true
        ? g?.computedProgress ?? 0
        : g?.progress ?? 0;
    _milestones = <GoalMilestone>[...?g?.milestones];

    _minGapCtrl = TextEditingController(
      text: _scheduling.randomMinGapDays?.toString() ?? '',
    );
    _maxPerWeekCtrl = TextEditingController(
      text: _scheduling.randomMaxPerWeek?.toString() ?? '',
    );
    _maxPerMonthCtrl = TextEditingController(
      text: _scheduling.randomMaxPerMonth?.toString() ?? '',
    );
    _focusMinutesCtrl = TextEditingController(
      text: _focus.focusSeconds != null
          ? (_focus.focusSeconds! ~/ 60).toString()
          : '',
    );
    _timeTargetCtrl = TextEditingController(
      text: g?.timeTargetSeconds != null
          ? (g!.timeTargetSeconds! ~/ 60).toString()
          : '',
    );
    _dailyCountCtrl = TextEditingController(
      text: g?.dailyTargetCount?.toString() ?? '',
    );
    _milestoneCtrl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _origin ??= GoalEditorOrigin.capture(context);
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  bool _canAct() => mounted && _origin?.isCurrent(context) == true;

  Future<void> _openIconPicker() async {
    final origin = _origin;
    final workspace = _workspaceId;
    if (origin == null || !_canAct() || !origin.canEdit(workspace)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await _showGoalIconPicker(
      context,
      _iconName,
      canAct: (sheetContext) =>
          mounted &&
          sheetContext.mounted &&
          origin.isCurrent(context, checkRoute: false) &&
          origin.canEdit(workspace) &&
          ModalRoute.of(sheetContext)?.isCurrent == true,
    );
    if (picked == null || !_canAct() || !origin.canEdit(workspace)) return;
    setState(() => _iconName = picked);
  }

  String _draftFingerprint(GoalItem item) {
    final data = item.toJson()..remove('updatedAt');
    return jsonEncode(data);
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _minGapCtrl.dispose();
    _maxPerWeekCtrl.dispose();
    _maxPerMonthCtrl.dispose();
    _focusMinutesCtrl.dispose();
    _timeTargetCtrl.dispose();
    _dailyCountCtrl.dispose();
    _milestoneCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  GoalItem _composeItem() {
    return GoalItem(
      id: _editingId,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      icon: _iconName,
      colorValue: _colorValue,
      startDate: _startDate,
      targetDate: _targetDate,
      status: _status,
      autoProgress: _autoProgress,
      progress: _autoProgress ? _currentAutoProgress() : _manualProgress,
      milestones: _milestones,
      category: widget.goal?.category ?? GoalCategory.custom,
      recurrence: _recurrence,
      scheduling: _scheduling,
      skipHolidays: _skipHolidays,
      focusLink: _focus,
      reminder: _reminderPlan.toLegacyReminderConfig(fallback: _reminder),
      reminderPlan: _reminderPlan,
      timeTargetSeconds: _parsePositiveInt(
        _timeTargetCtrl.text,
      ).let((min) => min * 60),
      dailyTargetCount: _parsePositiveInt(_dailyCountCtrl.text),
      sortOrder: widget.goal?.sortOrder ?? 0,
      workspaceId: _workspaceId,
      createdAt: _createdAt,
    );
  }

  Future<bool> _persist({required bool pop}) async {
    final origin = _origin;
    if (_persisting || origin == null || !_canAct()) return false;
    setState(() => _persisting = true);
    try {
      if (_titleCtrl.text.trim().isEmpty) {
        _showFeedback(
          (locale) => _goalText('请填写目标标题', 'Enter a goal title', locale),
          error: true,
        );
        return false;
      }
      final item = _composeItem();
      final issues = validateGoal(item);
      if (issues.isNotEmpty) {
        _showFeedback(
          (locale) =>
              issues.first.localizedMessage(isEnglish: locale == AppLocale.en),
          error: true,
        );
        return false;
      }
      if (!_canEditWorkspace(_workspaceId)) {
        _showFeedback(
          (locale) => _goalText(
            '你在这个共享空间中只有查看权限',
            'You have view-only access to this shared space',
            locale,
          ),
          error: true,
        );
        return false;
      }
      final provider = origin.provider;
      // The live form can change while storage is pending. Remember exactly
      // what was submitted so later edits still require their own save.
      final submittedFingerprint = _draftFingerprint(item);
      if (_acknowledgedDraft != submittedFingerprint) {
        bool canWrite() =>
            mounted &&
            origin.isCurrent(context, checkRoute: false, checkAccess: false) &&
            origin.canEdit(item.workspaceId);
        if (!_isExisting) {
          await provider.add(item, canWrite: canWrite);
        } else {
          await provider.update(item, canWrite: canWrite);
        }
        if (!mounted ||
            !origin.isCurrent(context, checkRoute: false, checkAccess: false)) {
          return true;
        }
        // ACK bookkeeping precedes navigation/access checks. A covered or
        // locked successful save must keep its ID rather than create again.
        _editingId = item.id;
        _createdAt = item.createdAt;
        _acknowledgedDraft = submittedFingerprint;
      }
      if (!_canAct()) return true;
      if (pop && _acknowledgedDraft != _draftFingerprint(_composeItem())) {
        _showFeedback(
          (locale) => _goalText(
            '已保存提交内容，新修改还需保存',
            'Submitted changes saved. Save your latest edits.',
            locale,
          ),
        );
      } else if (pop) {
        Navigator.pop(context);
      } else {
        _showSaved();
      }
      return true;
    } on AccountPreferenceWriteCanceled {
      return false;
    } catch (_) {
      if (_canAct()) {
        _showFeedback(
          (locale) =>
              _goalText('保存失败，请重试', 'Could not save. Try again.', locale),
          error: true,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _persisting = false);
      }
    }
  }

  Future<void> _pickFocusNoise(String id) async {
    if (!_canAct()) return;
    setState(() => _focus = _focus.copyWith(whiteNoise: id));
    if (id == FocusSoundCatalog.none) {
      await FocusSoundService.instance.stop();
      return;
    }
    final volume =
        context.read<PomodoroProvider?>()?.config.focusSoundVolume ??
        FocusSoundService.defaultVolume;
    await FocusSoundService.instance.setVolume(volume);
    if (!_canAct()) return;
    final started = await FocusSoundService.instance.preview(id);
    if (!_canAct() || started) return;
    _showFeedback(
      (locale) => _goalText(
        '专注声音预览启动失败，请检查系统音量或音频资源',
        'Could not preview the sound. Check volume and audio files.',
        locale,
      ),
      error: true,
    );
  }

  void _showSaved() {
    _showFeedback((locale) => _goalText('已保存', 'Saved', locale));
  }

  void _showFeedback(String Function(AppLocale) message, {bool error = false}) {
    if (!_canAct()) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (_, locale, _) => Text(message(locale)),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? DesignTokens.resultError : null,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  bool _canEditWorkspace(String workspaceId) {
    return context.read<ShareProvider?>()?.canEdit(workspaceId) ?? true;
  }

  Future<void> _deleteCurrentGoal() async {
    final origin = _origin;
    if (_persisting || _editingId == null || origin == null || !_canAct()) {
      return;
    }
    if (!_canEditWorkspace(_workspaceId)) {
      _showFeedback(
        (locale) => _goalText(
          '你在这个共享空间中只有查看权限',
          'You have view-only access to this shared space',
          locale,
        ),
        error: true,
      );
      return;
    }
    setState(() => _persisting = true);
    final id = _editingId!;
    final workspace = _workspaceId;
    try {
      await origin.provider.delete(
        id,
        canWrite: () =>
            mounted &&
            origin.isCurrent(context, checkRoute: false, checkAccess: false) &&
            origin.canEdit(workspace),
      );
      if (mounted && _canAct()) Navigator.of(context).pop();
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      if (_canAct()) {
        _showFeedback(
          (locale) =>
              _goalText('删除失败，请重试', 'Could not delete. Try again.', locale),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _persisting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final shareProvider = context.watch<ShareProvider?>();
    final canEditCurrentWorkspace =
        (shareProvider?.canEdit(_workspaceId) ?? true) && _canAct();
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : null,
      appBar: AppBar(
        title: Text(
          _isExisting
              ? _goalText('编辑目标', 'Edit goal')
              : _goalText('新建目标', 'New goal'),
        ),
        actions: [
          if (_isExisting)
            IconButton(
              tooltip: _goalText('删除', 'Delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: canEditCurrentWorkspace && !_persisting
                  ? _deleteCurrentGoal
                  : null,
            ),
          IconButton(
            tooltip: _goalText('保存并返回', 'Save and return'),
            icon: _persisting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: canEditCurrentWorkspace && !_persisting
                ? () => _persist(pop: true)
                : null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spaceLg,
          DesignTokens.spaceMd,
          DesignTokens.spaceLg,
          DesignTokens.space3xl,
        ),
        children: [
          _BasicSection(
            titleCtrl: _titleCtrl,
            descCtrl: _descCtrl,
            startDate: _startDate,
            targetDate: _targetDate,
            status: _status,
            colorValue: _colorValue,
            iconName: _iconName,
            onPickStart: (d) => setState(() => _startDate = d),
            onPickTarget: (d) => setState(() => _targetDate = d),
            onStatus: (s) => setState(() => _status = s),
            onColor: (v) => setState(() => _colorValue = v),
            onIcon: _openIconPicker,
            onSave: () => _persist(pop: false),
          ),
          _WorkspaceSection(
            workspaceId: _workspaceId,
            shareProvider: shareProvider,
            onChanged: (value) => setState(() {
              _workspaceId = _normalizeWorkspaceId(value);
            }),
            onSave: () => _persist(pop: false),
          ),
          _RecurrenceSection(
            rule: _recurrence,
            nextDispatchLabel: _nextDispatchLabel(
              AppDateFormat.patternOf(context),
            ),
            onPick: () async {
              if (!_canAct()) return;
              final r = await RecurrencePicker.show(
                context,
                initial: _recurrence,
                supportMaxOccurrences: false,
              );
              if (mounted && _canAct() && r != null) {
                setState(() => _recurrence = r);
              }
            },
            onSave: () => _persist(pop: false),
          ),
          _SchedulingSection(
            scheduling: _scheduling,
            recurrence: _recurrence,
            minGapCtrl: _minGapCtrl,
            maxPerWeekCtrl: _maxPerWeekCtrl,
            maxPerMonthCtrl: _maxPerMonthCtrl,
            onModeChange: (mode) => setState(() {
              _scheduling = _scheduling.copyWith(mode: mode);
            }),
            onWeekdaysChange: (days) => setState(() {
              _scheduling = GoalScheduling(
                mode: _scheduling.mode,
                fixedWeekdays: days.isEmpty
                    ? null
                    : List<int>.unmodifiable(days),
                fixedMonthDays: _scheduling.fixedMonthDays,
                randomMinGapDays: _scheduling.randomMinGapDays,
                randomMaxPerWeek: _scheduling.randomMaxPerWeek,
                randomMaxPerMonth: _scheduling.randomMaxPerMonth,
              );
            }),
            onMonthDaysChange: (days) => setState(() {
              _scheduling = GoalScheduling(
                mode: _scheduling.mode,
                fixedWeekdays: _scheduling.fixedWeekdays,
                fixedMonthDays: days.isEmpty
                    ? null
                    : List<int>.unmodifiable(days),
                randomMinGapDays: _scheduling.randomMinGapDays,
                randomMaxPerWeek: _scheduling.randomMaxPerWeek,
                randomMaxPerMonth: _scheduling.randomMaxPerMonth,
              );
            }),
            onRandomChange: () => setState(() {
              _scheduling = GoalScheduling(
                mode: SchedulingMode.random,
                fixedWeekdays: _scheduling.fixedWeekdays,
                fixedMonthDays: _scheduling.fixedMonthDays,
                randomMinGapDays: _parsePositiveInt(_minGapCtrl.text),
                randomMaxPerWeek: _parsePositiveInt(_maxPerWeekCtrl.text),
                randomMaxPerMonth: _parsePositiveInt(_maxPerMonthCtrl.text),
              );
            }),
            onSave: () {
              // 随机模式下,输入框的改动尚未提交到 _scheduling,先同步一次。
              if (_scheduling.mode == SchedulingMode.random) {
                _scheduling = GoalScheduling(
                  mode: SchedulingMode.random,
                  fixedWeekdays: _scheduling.fixedWeekdays,
                  fixedMonthDays: _scheduling.fixedMonthDays,
                  randomMinGapDays: _parsePositiveInt(_minGapCtrl.text),
                  randomMaxPerWeek: _parsePositiveInt(_maxPerWeekCtrl.text),
                  randomMaxPerMonth: _parsePositiveInt(_maxPerMonthCtrl.text),
                );
              }
              _persist(pop: false);
            },
          ),
          _SkipHolidaysSection(
            enabled: _skipHolidays,
            onChange: (v) => setState(() => _skipHolidays = v),
            onSave: () => _persist(pop: false),
          ),
          _FocusSection(
            focus: _focus,
            minutesCtrl: _focusMinutesCtrl,
            onToggle: (v) => setState(() {
              _focus = _focus.copyWith(enabled: v);
            }),
            onPickPreset: (min) => setState(() {
              _focusMinutesCtrl.text = min.toString();
              _focus = _focus.copyWith(focusSeconds: min * 60);
            }),
            onMinutesChange: (v) {
              final min = _parsePositiveInt(v);
              setState(() {
                _focus = FocusLink(
                  enabled: _focus.enabled,
                  presetId: _focus.presetId,
                  focusSeconds: min == null ? null : min * 60,
                  whiteNoise: _focus.whiteNoise,
                );
              });
            },
            onPickNoise: _pickFocusNoise,
            onSave: () => _persist(pop: false),
          ),
          _SectionCard(
            title: _goalText('提醒', 'Reminders'),
            icon: Icons.notifications_active_outlined,
            subtitle: reminderPlanSummary(_reminderPlan),
            onSave: () => _persist(pop: false),
            children: [
              ReminderPlanEditor(
                plan: _reminderPlan,
                showHeader: false,
                allowAlarm: true,
                allowRelativeToDue: true,
                allowWeekly: true,
                hasAnchorDate: _targetDate != null,
                defaultKind: ReminderKind.push,
                onChanged: (plan) => setState(() {
                  _reminderPlan = plan;
                  _reminder = plan.toLegacyReminderConfig(fallback: _reminder);
                }),
              ),
              const SizedBox(height: DesignTokens.spaceSm),
              Builder(
                builder: (context) {
                  final notif = context.watch<NotificationService?>();
                  if (notif == null) return const SizedBox.shrink();
                  final kind =
                      _reminderPlan.primaryRule?.kind ?? _reminder.kind;
                  return ReminderHealthHint(
                    reminderKind: kind,
                    onOpenSystemSettings: () async {
                      if (_canAct()) await openAppSettings();
                    },
                    onRequestNotificationPermission: () async {
                      if (!_canAct()) return;
                      await context
                          .read<NotificationService>()
                          .requestPermission();
                    },
                    onRequestExactAlarmPermission: () async {
                      if (!_canAct()) return;
                      await AlarmService.instance.requestExactAlarmPermission();
                    },
                    onRequestFullScreenIntentPermission: () async {
                      if (!_canAct()) return;
                      await AlarmService.instance
                          .requestFullScreenIntentPermission();
                    },
                  );
                },
              ),
            ],
          ),
          _TimeTargetSection(
            controller: _timeTargetCtrl,
            onClear: () {
              setState(() {
                _timeTargetCtrl.clear();
              });
            },
            onSave: () => _persist(pop: false),
          ),
          _DailyCountSection(
            controller: _dailyCountCtrl,
            onInc: () {
              final v = _parsePositiveInt(_dailyCountCtrl.text) ?? 0;
              setState(() {
                _dailyCountCtrl.text = (v + 1).toString();
              });
            },
            onDec: () {
              final v = _parsePositiveInt(_dailyCountCtrl.text) ?? 0;
              final next = v - 1;
              setState(() {
                _dailyCountCtrl.text = next <= 0 ? '' : next.toString();
              });
            },
            onChanged: (_) => setState(() {}),
            onSave: () => _persist(pop: false),
          ),
          _MilestonesSection(
            milestones: _milestones,
            controller: _milestoneCtrl,
            autoProgress: _autoProgress,
            manualProgress: _manualProgress,
            onToggle: (m, v) => setState(() {
              m.isCompleted = v;
              m.completedAt = v ? DateTime.now() : null;
            }),
            onRemove: (i) => setState(() {
              _milestones.removeAt(i);
            }),
            onAdd: (title) => setState(() {
              _milestones.add(GoalMilestone(title: title));
              _milestoneCtrl.clear();
            }),
            onAutoChange: (v) => setState(() {
              if (!v) {
                _manualProgress = _currentAutoProgress();
              }
              _autoProgress = v;
            }),
            onManualChange: (v) => setState(() => _manualProgress = v),
          ),
        ],
      ),
    );

    if (!isLiquidGlass) {
      return scaffold;
    }

    final hasBrandSurface =
        DesktopEmbeddedHostScope.isHosted(context) ||
        context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
    if (hasBrandSurface) {
      return scaffold;
    }
    return Material(
      color: routeBackground,
      child: BrandBackground(child: scaffold),
    );
  }

  double _currentAutoProgress() {
    if (_milestones.isEmpty) {
      return _status == GoalStatus.achieved ? 1.0 : 0.0;
    }
    final done = _milestones.where((m) => m.isCompleted).length;
    return (done / _milestones.length).clamp(0.0, 1.0);
  }

  String _nextDispatchLabel(String? pattern) {
    if (_recurrence.frequency == RecurrenceFrequency.none) {
      return _goalText('不重复', 'Does not repeat');
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final effectiveStart = _goalEffectiveStartDay(
      startDate: _startDate,
      createdAt: _createdAt,
      fallback: now,
    );
    final searchFrom = effectiveStart.isAfter(today) ? effectiveStart : today;
    final anchor = searchFrom.subtract(const Duration(days: 1));
    final next = RecurrenceEngine.nextOccurrence(
      rule: _recurrence,
      scheduling: _scheduling,
      skipHolidays: _skipHolidays,
      anchor: anchor,
      goalId: _editingId,
    );
    if (next == null) return _goalText('无（已到终止日）', 'None (end date reached)');
    return I18nDateFormat.date(next, pattern: pattern);
  }
}

// ---------------------------------------------------------------------------
// Section: 基础信息
// ---------------------------------------------------------------------------

class _BasicSection extends StatelessWidget {
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final DateTime? startDate;
  final DateTime? targetDate;
  final GoalStatus status;
  final int colorValue;
  final String iconName;
  final ValueChanged<DateTime?> onPickStart;
  final ValueChanged<DateTime?> onPickTarget;
  final ValueChanged<GoalStatus> onStatus;
  final ValueChanged<int> onColor;
  final VoidCallback onIcon;
  final VoidCallback onSave;

  const _BasicSection({
    required this.titleCtrl,
    required this.descCtrl,
    required this.startDate,
    required this.targetDate,
    required this.status,
    required this.colorValue,
    required this.iconName,
    required this.onPickStart,
    required this.onPickTarget,
    required this.onStatus,
    required this.onColor,
    required this.onIcon,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: _goalText('基础信息', 'Basics'),
      icon: Icons.flag_outlined,
      initiallyExpanded: true,
      onSave: onSave,
      children: [
        TextField(
          controller: titleCtrl,
          decoration: InputDecoration(
            labelText: _goalText('目标', 'Goal'),
            hintText: _goalText(
              '如：今年读 24 本书',
              'For example: read 24 books this year',
            ),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        TextField(
          controller: descCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: _goalText('描述 (可选)', 'Description (optional)'),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceLg),
        _GoalDateFields(
          startDate: startDate,
          targetDate: targetDate,
          onPickStart: onPickStart,
          onPickTarget: onPickTarget,
        ),
        const SizedBox(height: DesignTokens.spaceLg),
        Text(_goalText('颜色', 'Color'), style: _subtleLabel(context)),
        const SizedBox(height: DesignTokens.spaceXs),
        Wrap(
          spacing: DesignTokens.spaceSm,
          children: _presetColors.map((v) {
            final selected = v == colorValue;
            return GestureDetector(
              onTap: () => onColor(v),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(v),
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.58),
                          width: 0.45,
                        )
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: DesignTokens.spaceLg),
        Text(_goalText('图标', 'Icon'), style: _subtleLabel(context)),
        const SizedBox(height: DesignTokens.spaceXs),
        _GoalIconField(
          iconName: iconName,
          colorValue: colorValue,
          onPick: onIcon,
        ),
        const SizedBox(height: DesignTokens.spaceLg),
        Text(_goalText('状态', 'Status'), style: _subtleLabel(context)),
        const SizedBox(height: DesignTokens.spaceXs),
        Wrap(
          spacing: DesignTokens.spaceXs,
          children: GoalStatus.values.map((s) {
            final label = switch (s) {
              GoalStatus.active => _goalText('进行中', 'Active'),
              GoalStatus.paused => _goalText('暂停', 'Paused'),
              GoalStatus.achieved => _goalText('已达成', 'Achieved'),
              GoalStatus.abandoned => _goalText('放弃', 'Abandoned'),
            };
            return ChoiceChip(
              label: Text(label),
              selected: status == s,
              onSelected: (_) => onStatus(s),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _WorkspaceSection extends StatelessWidget {
  final String workspaceId;
  final ShareProvider? shareProvider;
  final ValueChanged<String> onChanged;
  final VoidCallback onSave;

  const _WorkspaceSection({
    required this.workspaceId,
    required this.shareProvider,
    required this.onChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final options = _workspaceOptions(shareProvider, workspaceId);
    final current = options.any((option) => option.id == workspaceId)
        ? workspaceId
        : 'private';
    final role = shareProvider?.roleFor(current) ?? WorkspaceRole.owner;
    final canEdit = shareProvider?.canEdit(current) ?? true;
    final subtitle = current == 'private'
        ? _goalText('个人空间', 'Personal space')
        : '${_workspaceLabel(options, current)} · ${role.label}';

    return _SectionCard(
      title: _goalText('空间归属', 'Workspace'),
      icon: Icons.groups_2_outlined,
      subtitle: subtitle,
      onSave: canEdit ? onSave : null,
      children: [
        AppSecondaryControlTheme(
          child: AppDropdownField<String>(
            initialValue: current,
            decoration: InputDecoration(
              labelText: _goalText('保存到', 'Save to'),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              isDense: true,
              contentPadding: EdgeInsets.fromLTRB(12, 16, 8, 10),
            ),
            items: options.map((option) {
              final optionRole = option.id == 'private'
                  ? WorkspaceRole.owner
                  : shareProvider?.roleFor(option.id) ?? WorkspaceRole.owner;
              final enabled =
                  canEdit && (option.id == 'private' || optionRole.canEdit);
              return DropdownMenuItem<String>(
                value: option.id,
                enabled: enabled,
                child: _WorkspaceOptionLabel(option: option, role: optionRole),
              );
            }).toList(),
            enabled: canEdit,
            onChanged: (value) {
              if (value == null) return;
              final nextRole = value == 'private'
                  ? WorkspaceRole.owner
                  : shareProvider?.roleFor(value) ?? WorkspaceRole.owner;
              if (!nextRole.canEdit) return;
              onChanged(value);
            },
          ),
        ),
        if (!canEdit) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          Text(
            _goalText(
              '你在这个共享空间中只有查看权限',
              'You have view-only access to this shared space',
            ),
            style: TextStyle(
              fontSize: DesignTokens.fontSizeSm,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _WorkspaceChoice {
  final String id;
  final String name;

  const _WorkspaceChoice({required this.id, required this.name});
}

class _WorkspaceOptionLabel extends StatelessWidget {
  final _WorkspaceChoice option;
  final WorkspaceRole role;

  const _WorkspaceOptionLabel({required this.option, required this.role});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPrivate = option.id == 'private';
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Icon(
          isPrivate ? Icons.person_outline : Icons.groups_2_outlined,
          size: 18,
        ),
        const SizedBox(width: DesignTokens.spaceXs),
        Expanded(
          child: Text(
            option.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!isPrivate) ...[
          const SizedBox(width: DesignTokens.spaceXs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 48),
            child: Text(
              role.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: cs.onSurface.withValues(alpha: 0.56),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GoalIconField extends StatelessWidget {
  final String iconName;
  final int colorValue;
  final VoidCallback onPick;

  const _GoalIconField({
    required this.iconName,
    required this.colorValue,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(colorValue);
    final icon = goalIconFromName(iconName);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: DesignTokens.borderRadiusSm,
        onTap: onPick,
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: DesignTokens.borderRadiusSm,
            border: Border.all(
              color: cs.outline.withValues(alpha: 0.22),
              width: 0.45,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceMd,
              vertical: DesignTokens.spaceSm,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: DesignTokens.borderRadiusMd,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: DesignTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goalIconLabel(iconName),
                        style: const TextStyle(
                          fontWeight: DesignTokens.fontWeightRegular,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _goalText('点击更换', 'Change icon'),
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeSm,
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: cs.onSurface.withValues(alpha: 0.46),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalDateFields extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? targetDate;
  final ValueChanged<DateTime?> onPickStart;
  final ValueChanged<DateTime?> onPickTarget;

  const _GoalDateFields({
    required this.startDate,
    required this.targetDate,
    required this.onPickStart,
    required this.onPickTarget,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 460;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DateField(
                key: const ValueKey('goal_start_date_field'),
                label: _goalText('开始日期', 'Start date'),
                date: startDate,
                emptyText: _goalText('创建即开启', 'On creation'),
                compact: compact,
                onPick: onPickStart,
              ),
            ),
            SizedBox(width: compact ? 6 : DesignTokens.spaceSm),
            Expanded(
              child: _DateField(
                key: const ValueKey('goal_target_date_field'),
                label: _goalText('目标日期', 'Target date'),
                date: targetDate,
                emptyText: _goalText('无期限', 'No deadline'),
                compact: compact,
                onPick: onPickTarget,
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<String?> _showGoalIconPicker(
  BuildContext context,
  String selected, {
  required bool Function(BuildContext) canAct,
}) {
  return showAppModalSheet<String>(
    context: context,
    builder: (context) => ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final cs = Theme.of(context).colorScheme;
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8);
        return AppModalSheet(
          title: _goalText('选择图标', 'Choose an icon', locale),
          scrollable: false,
          child: SizedBox(
            height: (MediaQuery.sizeOf(context).height * 0.5).clamp(
              120.0,
              420.0,
            ),
            child: GridView.builder(
              padding: EdgeInsets.zero,
              itemCount: goalIconChoices.length,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140 * scale,
                mainAxisExtent: 82 * scale,
                mainAxisSpacing: DesignTokens.spaceSm,
                crossAxisSpacing: DesignTokens.spaceSm,
              ),
              itemBuilder: (context, index) {
                final choice = goalIconChoices[index];
                final isSelected = choice.name == selected;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: DesignTokens.borderRadiusMd,
                    onTap: () {
                      if (canAct(context)) Navigator.pop(context, choice.name);
                    },
                    child: Ink(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? choice.color.withValues(alpha: 0.14)
                            : cs.surfaceContainerHighest.withValues(
                                alpha: 0.36,
                              ),
                        borderRadius: DesignTokens.borderRadiusMd,
                        border: Border.all(
                          color: isSelected
                              ? choice.color
                              : cs.outline.withValues(alpha: 0.16),
                          width: 0.45,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  choice.icon,
                                  color: choice.color,
                                  size: 24,
                                ),
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Text(
                                    choice.localizedLabel(locale),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: DesignTokens.fontSizeXs,
                                      fontWeight:
                                          DesignTokens.fontWeightRegular,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.76,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Icon(
                                Icons.check_circle,
                                size: 16,
                                color: choice.color,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Section: 重复规则
// ---------------------------------------------------------------------------

class _RecurrenceSection extends StatelessWidget {
  final RecurrenceRule rule;
  final String nextDispatchLabel;
  final VoidCallback onPick;
  final VoidCallback onSave;

  const _RecurrenceSection({
    required this.rule,
    required this.nextDispatchLabel,
    required this.onPick,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: _goalText('重复规则', 'Repeat rule'),
      icon: Icons.repeat,
      subtitle: rule.displayLabel(
        datePattern: AppDateFormat.patternOf(context),
      ),
      onSave: onSave,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.tune),
          title: Text(_goalText('编辑重复规则', 'Edit repeat rule')),
          subtitle: Text(
            rule.displayLabel(datePattern: AppDateFormat.patternOf(context)),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onPick,
        ),
        const SizedBox(height: DesignTokens.spaceXs),
        Container(
          padding: const EdgeInsets.all(DesignTokens.spaceMd),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.06),
            borderRadius: DesignTokens.borderRadiusSm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.event_available,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: DesignTokens.spaceXs,
                  runSpacing: DesignTokens.spaceXs,
                  children: [
                    Text(
                      _goalText('下一次派发日：', 'Next scheduled date: '),
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeSm,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      nextDispatchLabel,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeBase,
                        fontWeight: DesignTokens.fontWeightRegular,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 调度模式
// ---------------------------------------------------------------------------

class _SchedulingSection extends StatelessWidget {
  final GoalScheduling scheduling;
  final RecurrenceRule recurrence;
  final TextEditingController minGapCtrl;
  final TextEditingController maxPerWeekCtrl;
  final TextEditingController maxPerMonthCtrl;
  final ValueChanged<SchedulingMode> onModeChange;
  final ValueChanged<List<int>> onWeekdaysChange;
  final ValueChanged<List<int>> onMonthDaysChange;
  final VoidCallback onRandomChange;
  final VoidCallback onSave;

  const _SchedulingSection({
    required this.scheduling,
    required this.recurrence,
    required this.minGapCtrl,
    required this.maxPerWeekCtrl,
    required this.maxPerMonthCtrl,
    required this.onModeChange,
    required this.onWeekdaysChange,
    required this.onMonthDaysChange,
    required this.onRandomChange,
    required this.onSave,
  });

  String _subtitle() {
    if (scheduling.mode == SchedulingMode.random) {
      return _goalText('随机派发', 'Random schedule');
    }
    if (recurrence.frequency == RecurrenceFrequency.weekly &&
        (scheduling.fixedWeekdays?.isNotEmpty ?? false)) {
      final days = ([
        ...scheduling.fixedWeekdays!,
      ]..sort()).where((d) => d >= 0 && d < 7).map(_goalWeekday).join('/');
      return _goalText('固定 · $days', 'Fixed · $days');
    }
    if (recurrence.frequency == RecurrenceFrequency.monthly &&
        (scheduling.fixedMonthDays?.isNotEmpty ?? false)) {
      final days = ([...scheduling.fixedMonthDays!]..sort()).join('/');
      return _goalText('固定 · 每月 $days 号', 'Fixed · Month days $days');
    }
    return _goalText('固定派发', 'Fixed schedule');
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: _goalText('调度模式', 'Scheduling'),
      icon: Icons.tune,
      subtitle: _subtitle(),
      onSave: onSave,
      children: [
        SegmentedButton<SchedulingMode>(
          segments: [
            ButtonSegment(
              value: SchedulingMode.fixed,
              label: Text(_goalText('固定', 'Fixed')),
              icon: Icon(Icons.calendar_view_week),
            ),
            ButtonSegment(
              value: SchedulingMode.random,
              label: Text(_goalText('随机', 'Random')),
              icon: Icon(Icons.shuffle),
            ),
          ],
          selected: {scheduling.mode},
          onSelectionChanged: (s) => onModeChange(s.first),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        if (scheduling.mode == SchedulingMode.fixed)
          _FixedScheduling(
            scheduling: scheduling,
            recurrence: recurrence,
            onWeekdaysChange: onWeekdaysChange,
            onMonthDaysChange: onMonthDaysChange,
          )
        else
          _RandomScheduling(
            minGapCtrl: minGapCtrl,
            maxPerWeekCtrl: maxPerWeekCtrl,
            maxPerMonthCtrl: maxPerMonthCtrl,
            onChanged: onRandomChange,
          ),
      ],
    );
  }
}

class _FixedScheduling extends StatelessWidget {
  final GoalScheduling scheduling;
  final RecurrenceRule recurrence;
  final ValueChanged<List<int>> onWeekdaysChange;
  final ValueChanged<List<int>> onMonthDaysChange;

  const _FixedScheduling({
    required this.scheduling,
    required this.recurrence,
    required this.onWeekdaysChange,
    required this.onMonthDaysChange,
  });

  @override
  Widget build(BuildContext context) {
    if (recurrence.frequency == RecurrenceFrequency.weekly) {
      final selected = <int>{...?scheduling.fixedWeekdays};
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _goalText('每周派发日', 'Days of the week'),
            style: _subtleLabel(context),
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceXs,
            children: List.generate(7, (i) {
              final isSel = selected.contains(i);
              return FilterChip(
                label: Text(_goalWeekday(i)),
                selected: isSel,
                showCheckmark: false,
                onSelected: (_) {
                  final next = {...selected};
                  if (isSel) {
                    next.remove(i);
                  } else {
                    next.add(i);
                  }
                  onWeekdaysChange(next.toList()..sort());
                },
              );
            }),
          ),
        ],
      );
    }
    if (recurrence.frequency == RecurrenceFrequency.monthly) {
      final selected = <int>{...?scheduling.fixedMonthDays};
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _goalText('每月派发日（1~31）', 'Days of the month (1–31)'),
            style: _subtleLabel(context),
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceXs,
            runSpacing: DesignTokens.spaceXs,
            children: List.generate(31, (i) {
              final day = i + 1;
              final isSel = selected.contains(day);
              return FilterChip(
                label: Text('$day'),
                selected: isSel,
                showCheckmark: false,
                onSelected: (_) {
                  final next = {...selected};
                  if (isSel) {
                    next.remove(day);
                  } else {
                    next.add(day);
                  }
                  onMonthDaysChange(next.toList()..sort());
                },
              );
            }),
          ),
        ],
      );
    }
    return Text(
      _goalText(
        '当前重复规则下无需额外配置固定派发日。',
        'This repeat rule needs no extra scheduled days.',
      ),
      style: TextStyle(
        fontSize: DesignTokens.fontSizeSm,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }
}

class _RandomScheduling extends StatelessWidget {
  final TextEditingController minGapCtrl;
  final TextEditingController maxPerWeekCtrl;
  final TextEditingController maxPerMonthCtrl;
  final VoidCallback onChanged;

  const _RandomScheduling({
    required this.minGapCtrl,
    required this.maxPerWeekCtrl,
    required this.maxPerMonthCtrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RandomRow(
          label: _goalText('最小间隔天数', 'Minimum interval (days)'),
          hint: '≥ 1',
          controller: minGapCtrl,
          onChanged: onChanged,
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        _RandomRow(
          label: _goalText('每周最多派发次数', 'Weekly limit'),
          hint: _goalText('留空 = 不限', 'Blank = unlimited'),
          controller: maxPerWeekCtrl,
          onChanged: onChanged,
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        _RandomRow(
          label: _goalText('每月最多派发次数', 'Monthly limit'),
          hint: _goalText('留空 = 不限', 'Blank = unlimited'),
          controller: maxPerMonthCtrl,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RandomRow extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _RandomRow({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 3, child: Text(label, style: _subtleLabel(context))),
        Expanded(
          flex: 2,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(isDense: true, hintText: hint),
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 跳过节假日
// ---------------------------------------------------------------------------

class _SkipHolidaysSection extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChange;
  final VoidCallback onSave;

  const _SkipHolidaysSection({
    required this.enabled,
    required this.onChange,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: _goalText('跳过节假日', 'Skip holidays'),
      icon: Icons.beach_access,
      subtitle: enabled ? _goalText('已开启', 'On') : _goalText('已关闭', 'Off'),
      onSave: onSave,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          title: Text(_goalText('遇法定节假日顺延', 'Move past public holidays')),
          subtitle: Text(
            _goalText(
              '派发日遇节假日时自动跳到下一个工作日',
              'Schedule on the next working day after a holiday',
            ),
          ),
          onChanged: onChange,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 专注联动
// ---------------------------------------------------------------------------

class _FocusSection extends StatelessWidget {
  final FocusLink focus;
  final TextEditingController minutesCtrl;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onPickPreset;
  final ValueChanged<String> onMinutesChange;
  final ValueChanged<String> onPickNoise;
  final VoidCallback onSave;

  const _FocusSection({
    required this.focus,
    required this.minutesCtrl,
    required this.onToggle,
    required this.onPickPreset,
    required this.onMinutesChange,
    required this.onPickNoise,
    required this.onSave,
  });

  String _subtitle(BuildContext context) {
    if (!focus.enabled) return _goalText('已关闭', 'Off');
    final sec = focus.focusSeconds;
    final min = (sec == null || sec <= 0) ? null : sec ~/ 60;
    final custom = context.watch<CustomFocusSoundProvider>();
    final noise = custom.isCustomSound(focus.whiteNoise)
        ? custom.labelFor(focus.whiteNoise)
        : FocusSoundCatalog.labelFor(focus.whiteNoise);
    if (min == null) return _goalText('已开启 · $noise', 'On · $noise');
    return _goalText('$min 分钟 · $noise', '$min min · $noise');
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: _goalText('专注联动', 'Focus integration'),
      icon: Icons.timer_outlined,
      subtitle: _subtitle(context),
      onSave: onSave,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: focus.enabled,
          title: Text(_goalText('开启专注联动', 'Enable focus integration')),
          subtitle: Text(
            _goalText(
              '派发时自动跳转番茄钟,并播放白噪音',
              'Open the focus timer and play white noise when scheduled',
            ),
          ),
          onChanged: onToggle,
        ),
        if (focus.enabled) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          Text(
            _goalText('专注时长', 'Focus duration'),
            style: _subtleLabel(context),
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceXs,
            children: _focusMinutePresets.map((m) {
              final selected = focus.focusSeconds == m * 60;
              return ChoiceChip(
                label: Text(_goalText('$m 分钟', '$m min')),
                selected: selected,
                onSelected: (_) => onPickPreset(m),
              );
            }).toList(),
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  _goalText('自定义分钟', 'Custom minutes'),
                  style: _subtleLabel(context),
                ),
              ),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: minutesCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _goalText('留空 = 未设定', 'Blank = unset'),
                  ),
                  onChanged: onMinutesChange,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          Text(_goalText('白噪音', 'White noise'), style: _subtleLabel(context)),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceXs,
            runSpacing: DesignTokens.spaceXs,
            children: [
              for (final opt in FocusSoundCatalog.options)
                ChoiceChip(
                  label: Text(opt.label),
                  selected: focus.whiteNoise == opt.id,
                  onSelected: (_) => onPickNoise(opt.id),
                ),
              for (final sound
                  in context.watch<CustomFocusSoundProvider>().sounds)
                ChoiceChip(
                  avatar: const Icon(Icons.audio_file_outlined, size: 16),
                  label: Text(sound.label),
                  selected: focus.whiteNoise == sound.id,
                  onSelected: (_) => onPickNoise(sound.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 目标时长
// ---------------------------------------------------------------------------

class _TimeTargetSection extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onClear;
  final VoidCallback onSave;

  const _TimeTargetSection({
    required this.controller,
    required this.onClear,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final min = int.tryParse(controller.text.trim());
    final subtitle = (min == null || min <= 0)
        ? _goalText('未设置', 'Not set')
        : _goalText('$min 分钟 / 每次', '$min min / session');
    return _SectionCard(
      title: _goalText('目标时长', 'Target duration'),
      icon: Icons.hourglass_bottom,
      subtitle: subtitle,
      onSave: onSave,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                _goalText('每次时长（分钟）', 'Minutes per session'),
                style: _subtleLabel(context),
              ),
            ),
            Expanded(
              flex: 2,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _goalText('0 或留空 = 清除', '0 or blank = clear'),
                ),
              ),
            ),
            IconButton(
              tooltip: _goalText('清除', 'Clear'),
              icon: const Icon(Icons.clear),
              onPressed: onClear,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 每日次数
// ---------------------------------------------------------------------------

class _DailyCountSection extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final ValueChanged<String> onChanged;
  final VoidCallback onSave;

  const _DailyCountSection({
    required this.controller,
    required this.onInc,
    required this.onDec,
    required this.onChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(controller.text.trim());
    final subtitle = (n == null || n <= 0)
        ? _goalText('未设置', 'Not set')
        : _goalText('每日 $n 次', '$n per day');
    return _SectionCard(
      title: _goalText('每日次数', 'Daily count'),
      icon: Icons.format_list_numbered,
      subtitle: subtitle,
      onSave: onSave,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                _goalText('每日目标次数', 'Daily target count'),
                style: _subtleLabel(context),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: onDec,
            ),
            SizedBox(
              width: 72,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(isDense: true, hintText: '0'),
                onChanged: onChanged,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onInc,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 里程碑 + 自动进度
// ---------------------------------------------------------------------------

class _MilestonesSection extends StatelessWidget {
  final List<GoalMilestone> milestones;
  final TextEditingController controller;
  final bool autoProgress;
  final double manualProgress;
  final void Function(GoalMilestone, bool) onToggle;
  final ValueChanged<int> onRemove;
  final ValueChanged<String> onAdd;
  final ValueChanged<bool> onAutoChange;
  final ValueChanged<double> onManualChange;

  const _MilestonesSection({
    required this.milestones,
    required this.controller,
    required this.autoProgress,
    required this.manualProgress,
    required this.onToggle,
    required this.onRemove,
    required this.onAdd,
    required this.onAutoChange,
    required this.onManualChange,
  });

  @override
  Widget build(BuildContext context) {
    final completed = milestones.where((m) => m.isCompleted).length;
    return _SectionCard(
      title: _goalText('里程碑与进度', 'Milestones and progress'),
      icon: Icons.flag_circle_outlined,
      subtitle:
          '$completed/${milestones.length} · '
          '${autoProgress ? _goalText('自动', 'Automatic') : _goalText('手动 ${(manualProgress * 100).toInt()}%', 'Manual ${(manualProgress * 100).toInt()}%')}',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: autoProgress,
          title: Text(
            _goalText('按里程碑自动计算进度', 'Calculate progress from milestones'),
          ),
          subtitle: Text(
            autoProgress
                ? _goalText(
                    '完成度 = 已完成里程碑 / 总里程碑',
                    'Completed milestones / all milestones',
                  )
                : _goalText('手动设置当前进度', 'Set current progress manually'),
          ),
          onChanged: onAutoChange,
        ),
        if (!autoProgress)
          Row(
            children: [
              Text(_goalText('进度:', 'Progress:')),
              Expanded(
                child: Slider(
                  value: manualProgress,
                  onChanged: onManualChange,
                  label: '${(manualProgress * 100).toInt()}%',
                  divisions: 100,
                ),
              ),
              Text(
                '${(manualProgress * 100).toInt()}%',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        const SizedBox(height: DesignTokens.spaceSm),
        ...milestones.asMap().entries.map(
          (e) => Dismissible(
            key: ValueKey(e.value.id),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => onRemove(e.key),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: DesignTokens.spaceLg),
              color: DesignTokens.resultError,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            child: CheckboxListTile(
              value: e.value.isCompleted,
              onChanged: (v) => onToggle(e.value, v ?? false),
              title: Text(
                e.value.title,
                style: TextStyle(
                  decoration: e.value.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                  color: e.value.isCompleted
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: _goalText('添加里程碑', 'Add a milestone'),
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) onAdd(v.trim());
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                final v = controller.text.trim();
                if (v.isNotEmpty) onAdd(v);
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final bool initiallyExpanded;
  final VoidCallback? onSave;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surface = appSurfaceStyleOf(context);
    final radius = BorderRadius.circular(
      surface?.cardRadius ?? DesignTokens.radiusLg,
    );
    final titleStyle =
        (Theme.of(context).textTheme.titleMedium ??
                DefaultTextStyle.of(context).style)
            .copyWith(
              fontSize: DesignTokens.fontSizeMd,
              fontWeight: FontWeight.normal,
              color: cs.onSurface,
            );
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: DesignTokens.spaceMd),
      padding: EdgeInsets.zero,
      borderRadius: radius,
      border:
          surface?.cardBorder ??
          Border.all(color: cs.outline.withValues(alpha: 0.15), width: 0.45),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final titlePainter = TextPainter(
                text: TextSpan(text: title, style: titleStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                locale: Localizations.localeOf(context),
                maxLines: 1,
              )..layout();
              // Reserve the header's two affordances and its horizontal padding.
              final inlineWidth =
                  constraints.maxWidth -
                  2 * (DesignTokens.spaceLg + kMinInteractiveDimension);
              final stackedTitle = titlePainter.width > inlineWidth;
              titlePainter.dispose();
              final heading = Text(title, style: titleStyle);
              return ExpansionTile(
                initiallyExpanded: initiallyExpanded,
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spaceLg,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(
                  DesignTokens.spaceLg,
                  DesignTokens.spaceSm,
                  DesignTokens.spaceLg,
                  DesignTokens.spaceLg,
                ),
                leading: stackedTitle ? null : Icon(icon, color: cs.primary),
                title: stackedTitle
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: cs.primary),
                          const SizedBox(height: DesignTokens.spaceXs),
                          heading,
                        ],
                      )
                    : heading,
                subtitle: subtitle == null
                    ? null
                    : Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeSm,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                children: [
                  AppSecondaryControlTheme(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final String emptyText;
  final bool compact;
  final ValueChanged<DateTime?> onPick;

  const _DateField({
    super.key,
    required this.label,
    required this.date,
    required this.emptyText,
    this.compact = false,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasDate = date != null;
    final labelText = compact ? _compactDateFieldLabel(label) : label;
    final valueText = date == null
        ? emptyText
        : AppDateFormat.date(context, date!);
    final leadingIconSize = compact ? (hasDate ? 14.0 : 12.0) : 18.0;
    final valueFontSize = compact ? 11.0 : DesignTokens.fontSizeSm;
    final stacked =
        compact ||
        MediaQuery.textScalerOf(context).scale(valueFontSize) >
            valueFontSize * 1.25;
    final labelWidget = Text(
      labelText,
      style: TextStyle(
        fontSize: compact ? 11 : DesignTokens.fontSizeXs,
        color: cs.onSurface.withValues(alpha: 0.55),
      ),
    );
    final valueWidget = Text(
      valueText,
      textAlign: stacked ? TextAlign.start : TextAlign.end,
      style: TextStyle(
        fontSize: valueFontSize,
        fontWeight: FontWeight.normal,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return GestureDetector(
      onTap: () async {
        final picked = await AppDatePicker.pickSolar(
          context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2099, 12, 31),
          title: label,
        );
        if (!context.mounted) return;
        if (picked != null) onPick(picked);
      },
      child: Container(
        constraints: BoxConstraints(minHeight: compact ? 42 : 52),
        padding: compact
            ? const EdgeInsets.fromLTRB(6, 7, 4, 7)
            : const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.34),
          borderRadius: DesignTokens.borderRadiusMd,
          border: Border.all(
            color: cs.outline.withValues(alpha: 0.16),
            width: 0.45,
          ),
        ),
        child: Row(
          children: [
            if (compact && hasDate)
              Tooltip(
                message: _goalText('清除日期', 'Clear date'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(null),
                  child: SizedBox.square(
                    dimension: leadingIconSize,
                    child: Icon(
                      Icons.close,
                      size: leadingIconSize,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              )
            else
              Icon(
                Icons.calendar_today_outlined,
                size: leadingIconSize,
                color: cs.primary,
              ),
            SizedBox(width: compact ? 3 : DesignTokens.spaceXs),
            Expanded(
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        labelWidget,
                        const SizedBox(height: 2),
                        valueWidget,
                      ],
                    )
                  : Row(
                      children: [
                        labelWidget,
                        SizedBox(width: compact ? 2 : DesignTokens.spaceXs),
                        Expanded(child: valueWidget),
                      ],
                    ),
            ),
            if (date != null && !compact)
              IconButton(
                iconSize: compact ? 12 : 14,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: compact ? 18 : 24,
                  height: compact ? 18 : 24,
                ),
                icon: const Icon(Icons.close),
                onPressed: () => onPick(null),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _goalText(String chinese, String english, [AppLocale? locale]) =>
    (locale ?? I18n.current) == AppLocale.en ? english : chinese;

String _goalWeekday(int day) => I18n.tr(
  [
    'weekday.mon',
    'weekday.tue',
    'weekday.wed',
    'weekday.thu',
    'weekday.fri',
    'weekday.sat',
    'weekday.sun',
  ][day],
);

TextStyle _subtleLabel(BuildContext context) => TextStyle(
  fontSize: DesignTokens.fontSizeSm,
  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
);

String _compactDateFieldLabel(String label) {
  if (label == _goalText('开始日期', 'Start date')) return _goalText('开始', 'Start');
  if (label == _goalText('目标日期', 'Target date')) {
    return _goalText('目标', 'Target');
  }
  return label;
}

DateTime _goalEffectiveStartDay({
  required DateTime? startDate,
  required DateTime? createdAt,
  required DateTime fallback,
}) {
  final raw = startDate ?? createdAt ?? fallback;
  return DateTime(raw.year, raw.month, raw.day);
}

String _normalizeWorkspaceId(String? raw) {
  final value = raw?.trim();
  return value == null || value.isEmpty ? 'private' : value;
}

List<_WorkspaceChoice> _workspaceOptions(
  ShareProvider? shareProvider,
  String currentWorkspaceId,
) {
  final options = <_WorkspaceChoice>[
    _WorkspaceChoice(id: 'private', name: _goalText('个人空间', 'Personal space')),
  ];
  final known = <String>{'private'};
  for (final workspace in shareProvider?.workspaces ?? const <Workspace>[]) {
    if (workspace.isPrivate || workspace.id.isEmpty) continue;
    known.add(workspace.id);
    options.add(_WorkspaceChoice(id: workspace.id, name: workspace.name));
  }
  if (!known.contains(currentWorkspaceId) && currentWorkspaceId != 'private') {
    options.add(
      _WorkspaceChoice(
        id: currentWorkspaceId,
        name: _goalText('共享空间', 'Shared space'),
      ),
    );
  }
  return options;
}

String _workspaceLabel(List<_WorkspaceChoice> options, String workspaceId) {
  for (final option in options) {
    if (option.id == workspaceId) return option.name;
  }
  return _goalText('共享空间', 'Shared space');
}

/// 解析正整数输入；空串或非正整数返回 null。
int? _parsePositiveInt(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final n = int.tryParse(s);
  if (n == null || n <= 0) return null;
  return n;
}

extension _NullableIntMap on int? {
  /// `1.let((x) => x * 60)` → 60；`null.let(...)` → null。
  T? let<T>(T Function(int) fn) {
    final v = this;
    if (v == null) return null;
    return fn(v);
  }
}
