import '../widgets/app_date_format.dart';
import 'package:flutter/material.dart';
import '../services/app_haptics.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../core/account_preference_writes.dart';
import '../core/design_tokens.dart';
import '../core/habit_grouping.dart';
import '../core/habit_icons.dart';
import '../core/habit_trend.dart';
import '../core/habit_ui_copy.dart';
import '../core/habit_unit_draft.dart';
import '../core/i18n.dart';
import '../models/goal.dart'
    show ReminderKind, ReminderPlan, ReminderRule, ReminderRuleType;
import '../models/habit.dart';
import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/notification_service.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/alarm_service.dart';
import '../services/app_update_service.dart';
import '../widgets/brand_background.dart';
import '../widgets/controller_dialog.dart';
import '../widgets/habit_active_weekday_picker.dart';
import '../widgets/habit_date_range_fields.dart';
import '../widgets/habit_heatmap.dart';
import '../widgets/habit_unit_field.dart';
import '../widgets/reminder_health_hint.dart';
import '../widgets/reminder_plan_editor.dart';
import '../widgets/surface_components.dart';

const List<int> _habitEditColors = <int>[
  0xFF4CAF50,
  0xFF2196F3,
  0xFFFF9800,
  0xFFE91E63,
  0xFF9C27B0,
  0xFF00BCD4,
  0xFFFF5722,
  0xFF607D8B,
];

ButtonStyle _habitDangerFilledButtonStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: cs.error,
    foregroundColor: cs.onError,
    textStyle: appSecondaryMenuItemTextStyle(context),
    minimumSize: const Size(0, 36),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

ButtonStyle _habitDetailActionButtonStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return OutlinedButton.styleFrom(
    foregroundColor: cs.onSurface,
    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.32)),
    textStyle: appSecondaryControlTextStyle(context),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  );
}

ButtonStyle _habitDangerOutlinedButtonStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return OutlinedButton.styleFrom(
    foregroundColor: cs.error,
    side: BorderSide(color: cs.error.withValues(alpha: 0.42), width: 0.45),
    textStyle: appSecondaryControlTextStyle(context),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  );
}

class HabitActionOrigin {
  final HabitProvider habitProvider;
  final int accountGeneration;
  final AuthProvider? auth;
  final AuthSessionLease? sessionLease;
  final bool leaseCaptureFailed;
  String? _userId;
  final bool _wasLoggedIn;
  final int? _authSessionGeneration;
  final AppLockProvider? appLock;
  final AppUpdateService? appUpdate;
  final ModalRoute<dynamic>? ownerRoute;

  HabitActionOrigin._({
    required this.habitProvider,
    required this.accountGeneration,
    required this.auth,
    required this.sessionLease,
    required this.leaseCaptureFailed,
    required String? userId,
    required this.appLock,
    required this.appUpdate,
    required this.ownerRoute,
  }) : _userId = _normalizeUserId(userId),
       _wasLoggedIn = auth?.state.isLoggedIn ?? false,
       _authSessionGeneration = auth?.sessionGeneration;

  static String? _normalizeUserId(String? id) {
    if (id == null) return null;
    final trimmed = id.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static HabitActionOrigin? capture(BuildContext context) {
    try {
      final habitProvider = context.read<HabitProvider>();
      AuthProvider? auth;
      AuthSessionLease? lease;
      var failed = false;
      try {
        auth = context.read<AuthProvider?>();
        if (auth != null && auth.state.isLoggedIn) {
          try {
            lease = auth.captureSessionLease();
          } catch (_) {
            failed = true;
          }
        }
      } catch (_) {}

      AppLockProvider? lock;
      try {
        lock = context.read<AppLockProvider?>();
      } catch (_) {}

      AppUpdateService? update;
      try {
        update = context.read<AppUpdateService?>();
      } catch (_) {}

      return HabitActionOrigin._(
        habitProvider: habitProvider,
        accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
        auth: auth,
        sessionLease: lease,
        leaseCaptureFailed: failed,
        userId: auth?.state.userId,
        appLock: lock,
        appUpdate: update,
        ownerRoute: ModalRoute.of(context),
      );
    } catch (_) {
      return null;
    }
  }

  bool isAccessAllowed([BuildContext? context]) {
    AppLockProvider? lock = appLock;
    AppUpdateService? update = appUpdate;
    if (context != null && context.mounted) {
      try {
        lock = context.read<AppLockProvider?>() ?? lock;
      } catch (_) {}
      try {
        update = context.read<AppUpdateService?>() ?? update;
      } catch (_) {}
    }
    if (lock?.isLocked == true) return false;
    if (update?.mustUpdate == true) return false;
    return true;
  }

  bool isValid(
    BuildContext context, {
    bool checkCurrentRoute = true,
    bool checkAccess = true,
    ModalRoute<dynamic>? specificRoute,
  }) {
    if (!context.mounted) return false;
    if (leaseCaptureFailed) return false;
    if (checkAccess && !isAccessAllowed(context)) return false;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return false;
    }
    final targetRoute = specificRoute ?? ownerRoute;
    if (targetRoute != null) {
      if (!targetRoute.isActive) return false;
      if (checkCurrentRoute && !targetRoute.isCurrent) return false;
    }
    try {
      final currentHabit = context.read<HabitProvider>();
      if (!identical(currentHabit, habitProvider)) return false;

      if (auth != null) {
        final currentAuth = context.read<AuthProvider?>();
        if (!identical(currentAuth, auth)) return false;
        if (currentAuth!.sessionGeneration != _authSessionGeneration ||
            currentAuth.state.isLoggedIn != _wasLoggedIn ||
            currentAuth.isAccountTransitionInProgress ||
            currentAuth.isLocalAccountDataBlocked) {
          return false;
        }
        if (sessionLease != null &&
            !currentAuth.isSessionLeaseCurrent(sessionLease!)) {
          return false;
        }
        final currentUserId = _normalizeUserId(currentAuth.state.userId);
        if (_userId != null && currentUserId != _userId) return false;
        _userId ??= currentUserId;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

void showHabitSafeFeedback(
  BuildContext context,
  String Function(AppLocale locale) messageBuilder, {
  Duration duration = const Duration(milliseconds: 1400),
  Color? backgroundColor,
  HabitActionOrigin? origin,
  ModalRoute<dynamic>? route,
}) {
  if (!context.mounted) return;
  final effectiveRoute = route ?? ModalRoute.of(context);
  if (effectiveRoute != null && !effectiveRoute.isCurrent) return;
  if (origin != null &&
      !origin.isValid(
        context,
        checkCurrentRoute: true,
        specificRoute: effectiveRoute,
      )) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (_, locale, _) => Text(messageBuilder(locale)),
      ),
      behavior: SnackBarBehavior.floating,
      duration: duration,
      backgroundColor: backgroundColor,
    ),
  );
}

Future<bool> confirmHabitDelete(
  BuildContext context,
  Habit habit, {
  HabitActionOrigin? origin,
}) async {
  final authority = origin ?? HabitActionOrigin.capture(context);
  if (authority == null || !authority.isValid(context)) return false;
  final ok = await showControllerDialog<bool>(
    context: context,
    controllers: const [],
    builder: (ctx) => ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (ctx, locale, _) {
        void popDialog(bool result) {
          final route = ModalRoute.of(ctx);
          if (ctx.mounted &&
              route != null &&
              authority.isValid(ctx, specificRoute: route)) {
            Navigator.pop(ctx, result);
          }
        }

        return AppDialog(
          icon: Icon(
            Icons.delete_outline,
            color: Theme.of(ctx).colorScheme.error,
          ),
          title: Text(HabitUiCopy.deleteConfirmTitle(locale)),
          content: Text(HabitUiCopy.deleteConfirmContent(habit.name, locale)),
          actions: [
            TextButton(
              onPressed: () => popDialog(false),
              child: Text(HabitUiCopy.actionCancel(locale)),
            ),
            FilledButton(
              style: _habitDangerFilledButtonStyle(ctx),
              onPressed: () => popDialog(true),
              child: Text(HabitUiCopy.actionDelete(locale)),
            ),
          ],
        );
      },
    ),
  );
  return ok == true;
}

Future<bool> confirmHabitEnd(
  BuildContext context,
  Habit habit, {
  HabitActionOrigin? origin,
}) async {
  final authority = origin ?? HabitActionOrigin.capture(context);
  if (authority == null || !authority.isValid(context)) return false;
  final ok = await showControllerDialog<bool>(
    context: context,
    controllers: const [],
    builder: (ctx) => ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (ctx, locale, _) {
        void popDialog(bool result) {
          final route = ModalRoute.of(ctx);
          if (ctx.mounted &&
              route != null &&
              authority.isValid(ctx, specificRoute: route)) {
            Navigator.pop(ctx, result);
          }
        }

        return AppDialog(
          icon: Icon(
            Icons.event_busy_outlined,
            color: Theme.of(ctx).colorScheme.primary,
          ),
          title: Text(HabitUiCopy.endConfirmTitle(locale)),
          content: Text(HabitUiCopy.endConfirmContent(habit.name, locale)),
          actions: [
            TextButton(
              onPressed: () => popDialog(false),
              child: Text(HabitUiCopy.actionCancel(locale)),
            ),
            FilledButton(
              onPressed: () => popDialog(true),
              child: Text(HabitUiCopy.endHabitAction(locale)),
            ),
          ],
        );
      },
    ),
  );
  return ok == true;
}

Future<bool> _confirmHabitDelete(
  BuildContext context,
  Habit habit,
  HabitActionOrigin origin,
) => confirmHabitDelete(context, habit, origin: origin);

Future<bool> _confirmHabitEnd(
  BuildContext context,
  Habit habit,
  HabitActionOrigin origin,
) => confirmHabitEnd(context, habit, origin: origin);

Future<void> showHabitEditor(
  BuildContext context,
  Habit habit, {
  HabitActionOrigin? actionOrigin,
}) async {
  final rootRoute = ModalRoute.of(context);
  if (rootRoute == null || !rootRoute.isCurrent) return;

  final origin = actionOrigin ?? HabitActionOrigin.capture(context);
  if (origin == null || !origin.isValid(context, checkCurrentRoute: true)) {
    return;
  }

  final nameCtrl = TextEditingController(text: habit.name);
  final targetCtrl = TextEditingController(text: habit.targetCount.toString());
  final flexTargetCtrl = TextEditingController(
    text: (habit.flexTarget ?? habit.weeklyTarget).toString(),
  );
  final unitDraft = HabitUnitDraft(
    authoredUnit: habit.unit,
    generatedUnitKey: habit.generatedUnitKey,
  );
  final categoryCtrl = TextEditingController(text: habit.category ?? '');
  final tagsCtrl = TextEditingController(text: habit.tags.join(', '));
  var selectedColor = habit.colorValue;
  var selectedKind = habit.kind;
  var flexRuleEnabled = habit.hasFlexRule;
  var selectedFlexPeriod = habit.flexPeriod ?? HabitFlexPeriod.week;
  DateTime? startDate = habit.startDate;
  DateTime? endDate = habit.endDate;
  // 生效星期是显式配置的唯一事实来源；旧数据缺字段时 Habit 构造
  // 已回退全 7 天，这里再兜底一次空列表，避免表单出现"零生效日"。
  var selectedActiveWeekdays = habit.activeWeekdays.isEmpty
      ? List<int>.from(const [0, 1, 2, 3, 4, 5, 6])
      : List<int>.from(habit.activeWeekdays);
  var reminderPlan = _habitReminderPlan(habit);
  final previouslyHadReminder = _habitHasReminder(habit);
  var saving = false;
  Habit? completedResult;
  ModalRoute<dynamic>? ownedSheet;

  await showAppModalSheet(
    context: context,
    builder: (sheetCtx) => ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (sheetCtx, locale, _) => StatefulBuilder(
        builder: (sheetCtx, setSt) {
          ownedSheet ??= ModalRoute.of(sheetCtx);
          void changeDraft(VoidCallback change) {
            final route = ModalRoute.of(sheetCtx);
            if (saving ||
                !sheetCtx.mounted ||
                route == null ||
                !origin.isValid(sheetCtx, specificRoute: route)) {
              return;
            }
            setSt(change);
          }

          Future<void> save() async {
            final sheetRoute = ModalRoute.of(sheetCtx);
            if (!sheetCtx.mounted ||
                sheetRoute == null ||
                !sheetRoute.isCurrent) {
              return;
            }
            if (completedResult != null) {
              if (origin.isValid(sheetCtx, checkCurrentRoute: false)) {
                Navigator.of(sheetCtx).pop();
              }
              return;
            }
            if (saving) return;
            if (!origin.isValid(sheetCtx, specificRoute: sheetRoute)) return;

            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              showHabitSafeFeedback(
                sheetCtx,
                (loc) => HabitUiCopy.nameRequired(loc),
                origin: origin,
                route: sheetRoute,
              );
              return;
            }

            final target = int.tryParse(targetCtrl.text.trim()) ?? 1;
            if (target < 1) {
              showHabitSafeFeedback(
                sheetCtx,
                (loc) => HabitUiCopy.dailyTargetInvalid(loc),
                origin: origin,
                route: sheetRoute,
              );
              return;
            }
            final shouldUseFlex =
                flexRuleEnabled && selectedKind == HabitKind.positive;
            final flexTarget = int.tryParse(flexTargetCtrl.text.trim()) ?? 0;
            if (shouldUseFlex && flexTarget < 1) {
              showHabitSafeFeedback(
                sheetCtx,
                (loc) => HabitUiCopy.flexTargetInvalid(loc),
                origin: origin,
                route: sheetRoute,
              );
              return;
            }
            if (!habitDateRangeIsValid(startDate, endDate)) {
              showHabitSafeFeedback(
                sheetCtx,
                (loc) => HabitUiCopy.dateRangeInvalid(loc),
                origin: origin,
                route: sheetRoute,
              );
              return;
            }

            FocusScope.of(sheetCtx).unfocus();
            setSt(() => saving = true);
            try {
              final normalizedReminderPlan = _normalizeHabitReminderPlan(
                reminderPlan,
              );
              final reminderRules = _activeHabitReminderRules(
                normalizedReminderPlan,
              );
              final reminderRule = reminderRules.isEmpty
                  ? null
                  : reminderRules.first;
              final hasReminder =
                  normalizedReminderPlan.enabled && reminderRule != null;
              final nextActiveWeekdays = List<int>.from(selectedActiveWeekdays);
              final updated = habit.copyWith(
                name: name,
                targetCount: target,
                unit: unitDraft.authoredUnit,
                clearUnit: unitDraft.authoredUnit == null,
                generatedUnitKey: unitDraft.generatedUnitKey,
                clearGeneratedUnitKey: unitDraft.generatedUnitKey == null,
                category: habitCategoryOrNull(categoryCtrl.text),
                clearCategory:
                    normalizeHabitCategory(categoryCtrl.text) ==
                    defaultHabitCategoryName,
                tags: _parseHabitDetailTags(tagsCtrl.text),
                colorValue: selectedColor,
                kind: selectedKind,
                flexTarget: shouldUseFlex ? flexTarget : null,
                flexPeriod: shouldUseFlex ? selectedFlexPeriod : null,
                clearFlexRule: !shouldUseFlex,
                startDate: startDate,
                endDate: endDate,
                clearStartDate: startDate == null,
                clearEndDate: endDate == null,
                activeWeekdays: nextActiveWeekdays,
                remind: hasReminder,
                remindHour: hasReminder ? reminderRule.hour : null,
                remindMinute: hasReminder ? reminderRule.minute : null,
                reminderPlan: hasReminder
                    ? ReminderPlan(enabled: true, rules: reminderRules)
                    : const ReminderPlan.disabled(),
              );

              if (hasReminder) {
                final notificationService = sheetCtx
                    .read<NotificationService?>();
                final granted =
                    notificationService == null ||
                    await notificationService.ensureReadyForReminder(
                      scheduledTime: _nextHabitReminderTriggerForPlan(
                        reminderRules,
                      ),
                      issueTitle: HabitUiCopy.reminderRegisterFailed(locale),
                      relatedId: habit.id,
                    );
                if (!sheetCtx.mounted ||
                    !sheetRoute.isCurrent ||
                    !origin.isValid(sheetCtx, specificRoute: sheetRoute)) {
                  return;
                }
                if (!granted) {
                  final issue = notificationService.lastScheduleIssue;
                  showHabitSafeFeedback(
                    sheetCtx,
                    (loc) =>
                        issue?.message ??
                        HabitUiCopy.reminderPermissionError(loc),
                    origin: origin,
                    route: sheetRoute,
                  );
                  return;
                }
              }

              if (!sheetCtx.mounted ||
                  !origin.isValid(sheetCtx, checkCurrentRoute: false)) {
                return;
              }

              await origin.habitProvider.updateHabit(habit.id, updated);
              final reminderSyncIssue = (hasReminder || previouslyHadReminder)
                  ? origin.habitProvider.lastReminderSyncIssue
                  : null;

              if (!sheetCtx.mounted ||
                  !origin.isValid(
                    sheetCtx,
                    checkCurrentRoute: false,
                    checkAccess: false,
                  )) {
                return;
              }

              completedResult = updated;
              setSt(() => saving = false);

              if (origin.isValid(sheetCtx, specificRoute: sheetRoute)) {
                Navigator.of(sheetCtx).pop();
                showHabitSafeFeedback(
                  context,
                  (loc) => reminderSyncIssue == null
                      ? HabitUiCopy.saveSuccess(loc)
                      : HabitUiCopy.reminderSyncWarning(
                          _habitReminderSyncIssueText(reminderSyncIssue, loc),
                          loc,
                        ),
                  backgroundColor: reminderSyncIssue == null
                      ? null
                      : Theme.of(context).colorScheme.error,
                );
              }
            } on AccountPreferenceWriteCanceled {
              return;
            } catch (_) {
              if (!sheetCtx.mounted ||
                  !origin.isValid(sheetCtx, specificRoute: sheetRoute)) {
                return;
              }
              showHabitSafeFeedback(
                sheetCtx,
                (loc) => HabitUiCopy.saveFailedWithRetry(loc),
                origin: origin,
                route: sheetRoute,
              );
            } finally {
              if (sheetCtx.mounted && completedResult == null) {
                setSt(() => saving = false);
              }
            }
          }

          return AppModalSheet(
            title: I18n.tr('habit.edit.title'),
            subtitle: habit.name,
            actions: [
              TextButton(
                onPressed: () {
                  final route = ModalRoute.of(sheetCtx);
                  if (sheetCtx.mounted &&
                      route != null &&
                      origin.isValid(sheetCtx, specificRoute: route)) {
                    Navigator.of(sheetCtx).pop();
                  }
                },
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: saving ? null : save,
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(I18n.tr('action.save')),
              ),
            ],
            child: AbsorbPointer(
              absorbing: saving,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    enabled: !saving,
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: I18n.tr('habit.field.name'),
                      prefixIcon: const Icon(Icons.edit, size: 20),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceMd),
                  TextField(
                    enabled: !saving,
                    controller: categoryCtrl,
                    decoration: InputDecoration(
                      labelText: I18n.tr('habit.field.group'),
                      hintText: I18n.tr('habit.field.group.empty_hint'),
                      prefixIcon: const Icon(Icons.folder_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceMd),
                  TextField(
                    enabled: !saving,
                    controller: tagsCtrl,
                    decoration: InputDecoration(
                      labelText: I18n.current == AppLocale.en ? 'Tags' : '标签',
                      hintText: I18n.current == AppLocale.en
                          ? 'Comma separated, e.g. morning, health'
                          : '逗号或空格分隔，例如 晨间, 健康',
                      prefixIcon: const Icon(Icons.sell_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceMd),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          enabled: !saving,
                          controller: targetCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: I18n.tr(
                              'habit.field.daily_target_count',
                            ),
                            prefixIcon: const Icon(
                              Icons.track_changes,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spaceSm),
                      SizedBox(
                        width: 96,
                        child: HabitUnitField(
                          draft: unitDraft,
                          targetController: targetCtrl,
                          locale: locale,
                          enabled: !saving,
                          onChanged: (value) =>
                              changeDraft(() => unitDraft.recordEdit(value)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.spaceMd),
                  AppSurfaceCard(
                    padding: const EdgeInsets.all(DesignTokens.spaceMd),
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.tune, size: 18),
                            const SizedBox(width: DesignTokens.spaceSm),
                            Expanded(child: Text(I18n.tr('habit.flex.rule'))),
                            Switch(
                              value:
                                  flexRuleEnabled &&
                                  selectedKind == HabitKind.positive,
                              onChanged: selectedKind == HabitKind.positive
                                  ? (value) =>
                                        setSt(() => flexRuleEnabled = value)
                                  : null,
                            ),
                          ],
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child:
                              flexRuleEnabled &&
                                  selectedKind == HabitKind.positive
                              ? Padding(
                                  key: const ValueKey('habit-flex-edit-fields'),
                                  padding: const EdgeInsets.only(
                                    top: DesignTokens.spaceSm,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SegmentedButton<HabitFlexPeriod>(
                                        showSelectedIcon: false,
                                        segments: [
                                          ButtonSegment(
                                            value: HabitFlexPeriod.week,
                                            label: Text(
                                              I18n.tr('habit.flex.weekly'),
                                            ),
                                          ),
                                          ButtonSegment(
                                            value: HabitFlexPeriod.month,
                                            label: Text(
                                              I18n.tr('habit.flex.monthly'),
                                            ),
                                          ),
                                        ],
                                        selected: {selectedFlexPeriod},
                                        onSelectionChanged: (value) => setSt(
                                          () =>
                                              selectedFlexPeriod = value.first,
                                        ),
                                      ),
                                      const SizedBox(
                                        height: DesignTokens.spaceSm,
                                      ),
                                      TextField(
                                        enabled: !saving,
                                        controller: flexTargetCtrl,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: InputDecoration(
                                          labelText: I18n.tr(
                                            'habit.flex.period_target',
                                          ),
                                          hintText: I18n.tr(
                                            'habit.flex.period_target_hint',
                                          ),
                                          prefixIcon: const Icon(
                                            Icons.event_repeat,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Padding(
                                  key: const ValueKey('habit-daily-edit-note'),
                                  padding: const EdgeInsets.only(
                                    top: DesignTokens.spaceXs,
                                  ),
                                  child: Text(
                                    selectedKind == HabitKind.positive
                                        ? I18n.tr('habit.flex.daily_note')
                                        : I18n.tr('habit.flex.negative_note'),
                                    style: TextStyle(
                                      fontSize: DesignTokens.fontSizeSm,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceMd),
                  HabitDateRangeFields(
                    startDate: startDate,
                    endDate: endDate,
                    onStartChanged: (value) => setSt(() => startDate = value),
                    onEndChanged: (value) => setSt(() => endDate = value),
                  ),
                  const SizedBox(height: DesignTokens.spaceMd),
                  HabitActiveWeekdayPicker(
                    weekdays: selectedActiveWeekdays,
                    onChanged: (value) =>
                        setSt(() => selectedActiveWeekdays = value),
                    warning: _habitPlanHasWeeklyReminder(reminderPlan)
                        ? I18n.tr('habit.active_weekdays.reminder_hint')
                        : null,
                  ),
                  const SizedBox(height: DesignTokens.spaceMd),
                  Text(
                    I18n.tr('habit.kind'),
                    style: const TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      fontWeight: DesignTokens.fontWeightRegular,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXs),
                  Wrap(
                    spacing: DesignTokens.spaceSm,
                    runSpacing: DesignTokens.spaceSm,
                    children: [
                      ChoiceChip(
                        label: Text(I18n.tr('habit.kind.positive')),
                        selected: selectedKind == HabitKind.positive,
                        onSelected: (_) => setSt(() {
                          selectedKind = HabitKind.positive;
                        }),
                      ),
                      ChoiceChip(
                        label: Text(I18n.tr('habit.kind.negative')),
                        selected: selectedKind == HabitKind.negative,
                        onSelected: (_) => setSt(() {
                          selectedKind = HabitKind.negative;
                          flexRuleEnabled = false;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.spaceMd),
                  Text(
                    I18n.tr('habit.color'),
                    style: const TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      fontWeight: DesignTokens.fontWeightRegular,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXs),
                  Wrap(
                    spacing: DesignTokens.spaceSm,
                    runSpacing: DesignTokens.spaceSm,
                    children: [
                      for (final c in _habitEditColors)
                        GestureDetector(
                          onTap: () => setSt(() => selectedColor = c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: selectedColor == c
                                  ? Border.all(color: Colors.white, width: 1.2)
                                  : null,
                              boxShadow: selectedColor == c
                                  ? [
                                      BoxShadow(
                                        color: Color(c).withValues(alpha: 0.35),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.spaceMd),
                  ReminderPlanEditor(
                    plan: reminderPlan,
                    title: I18n.tr('habit.reminder'),
                    allowAlarm: true,
                    allowRelativeToDue: false,
                    allowWeekly: true,
                    allowSnooze: false,
                    hasAnchorDate: false,
                    maxRules: 12,
                    defaultKind: ReminderKind.popup,
                    showTypeSelector: false,
                    showKindSelector: false,
                    onChanged: (plan) => setSt(
                      () => reminderPlan = _normalizeHabitReminderPlan(plan),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceSm),
                  Builder(
                    builder: (context) {
                      final notif = context.watch<NotificationService?>();
                      if (notif == null) return const SizedBox.shrink();
                      final reminderKind =
                          _habitPrimaryReminder(reminderPlan)?.kind ??
                          ReminderKind.push;
                      return ReminderHealthHint(
                        reminderKind: reminderKind,
                        onOpenSystemSettings: () =>
                            _openSystemSettings(context, origin: origin),
                        onRequestNotificationPermission: () async {
                          final route = ModalRoute.of(context);
                          if (route == null ||
                              !origin.isValid(context, specificRoute: route)) {
                            return;
                          }
                          await context
                              .read<NotificationService>()
                              .requestPermission();
                        },
                        onRequestExactAlarmPermission: () async {
                          final route = ModalRoute.of(context);
                          if (route == null ||
                              !origin.isValid(context, specificRoute: route)) {
                            return;
                          }
                          await AlarmService.instance
                              .requestExactAlarmPermission();
                        },
                        onRequestFullScreenIntentPermission: () async {
                          final route = ModalRoute.of(context);
                          if (route == null ||
                              !origin.isValid(context, specificRoute: route)) {
                            return;
                          }
                          await AlarmService.instance
                              .requestFullScreenIntentPermission();
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  ).whenComplete(() async {
    await ownedSheet?.completed;
    nameCtrl.dispose();
    targetCtrl.dispose();
    flexTargetCtrl.dispose();
    unitDraft.dispose();
    categoryCtrl.dispose();
    tagsCtrl.dispose();
  });
}

List<String> _parseHabitDetailTags(String raw) {
  final out = <String>{};
  for (final part in raw.split(RegExp(r'[,，\s]+'))) {
    final trimmed = part.trim();
    if (trimmed.isNotEmpty) out.add(trimmed);
  }
  return out.toList();
}

class HabitDetailScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final String habitId;

  const HabitDetailScreen({super.key, required this.habitId});

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  DateTime? _pickedBackfillDate;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    super.dispose();
  }

  Future<void> _executeEndHabit(
    BuildContext context,
    Habit habit,
    HabitActionOrigin origin,
  ) async {
    if (!origin.isValid(context)) return;
    final ok = await _confirmHabitEnd(context, habit, origin);
    if (!ok ||
        !context.mounted ||
        !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    try {
      await origin.habitProvider.endHabit(habit.id);
      if (!context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      showHabitSafeFeedback(
        context,
        (loc) => HabitUiCopy.endedFeedback(loc),
        origin: origin,
      );
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      if (!context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      showHabitSafeFeedback(
        context,
        (loc) => HabitUiCopy.actionFailedWithRetry(loc),
        origin: origin,
      );
    }
  }

  Future<void> _executeDeleteHabit(
    BuildContext context,
    Habit habit,
    HabitActionOrigin origin,
  ) async {
    if (!origin.isValid(context)) return;
    final ok = await _confirmHabitDelete(context, habit, origin);
    if (!ok ||
        !context.mounted ||
        !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    try {
      await origin.habitProvider.deleteHabit(habit.id);
      if (!context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      showHabitSafeFeedback(
        context,
        (loc) => HabitUiCopy.deletedFeedback(loc),
        origin: origin,
      );
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) {
        Navigator.pop(context);
      }
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      if (!context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      showHabitSafeFeedback(
        context,
        (loc) => HabitUiCopy.actionFailedWithRetry(loc),
        origin: origin,
      );
    }
  }

  Future<void> _handleDateRecord(
    BuildContext context,
    Habit habit,
    DateTime date,
    HabitActionOrigin origin,
  ) async {
    if (!origin.isValid(context, checkCurrentRoute: true)) return;
    try {
      await origin.habitProvider.incrementHabitForDate(habit.id, date);
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      if (!context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      showHabitSafeFeedback(
        context,
        (loc) => HabitUiCopy.checkInFailedWithRetry(loc),
        origin: origin,
      );
      return;
    }
    if (!context.mounted || !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    await performAppHaptic(
      context,
      AppHaptic.mediumImpact,
      isCurrent: () => origin.isValid(context, checkCurrentRoute: true),
    );
    if (!context.mounted || !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    showHabitSafeFeedback(
      context,
      (loc) => HabitUiCopy.dateRecordFeedback(habit.name, date, loc),
      origin: origin,
    );
  }

  Future<void> _handleDateUndo(
    BuildContext context,
    Habit habit,
    DateTime date,
    HabitActionOrigin origin,
  ) async {
    if (!origin.isValid(context, checkCurrentRoute: true)) return;
    try {
      await origin.habitProvider.decrementHabitForDate(habit.id, date);
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      if (!context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      showHabitSafeFeedback(
        context,
        (loc) => HabitUiCopy.undoFailedWithRetry(loc),
        origin: origin,
      );
      return;
    }
    if (!context.mounted || !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    await performAppHaptic(
      context,
      AppHaptic.selectionClick,
      isCurrent: () => origin.isValid(context, checkCurrentRoute: true),
    );
    if (!context.mounted || !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    showHabitSafeFeedback(
      context,
      (loc) => HabitUiCopy.dateUndoFeedback(habit.name, date, loc),
      origin: origin,
    );
  }

  static Widget _wrapScaffold(BuildContext context, Widget scaffold) {
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    if (!isLiquidGlass) {
      return scaffold;
    }

    final hasBrandSurface =
        context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
    if (hasBrandSurface) {
      return scaffold;
    }
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Material(
      color: routeBackground,
      child: BrandBackground(child: scaffold),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final surfaceStyle = appSurfaceStyleOf(context);
        final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
        final provider = context.watch<HabitProvider>();
        final matches = provider.habits.where((h) => h.id == widget.habitId);
        if (matches.isEmpty) {
          final scaffold = Scaffold(
            backgroundColor: isLiquidGlass ? Colors.transparent : null,
            appBar: AppBar(
              title: Text(I18n.tr('habit.detail.title')),
              titleTextStyle: appSecondaryRouteTitleTextStyle(context),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.space3xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: DesignTokens.spaceMd),
                    Text(
                      I18n.tr('habit.detail.not_found'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: DesignTokens.spaceLg),
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                      label: Text(I18n.tr('action.back')),
                    ),
                  ],
                ),
              ),
            ),
          );
          return _wrapScaffold(context, scaffold);
        }
        final habit = matches.first;
        final origin = HabitActionOrigin.capture(context);
        final heatmapToday = DateTime.now();
        final heatmapData = habit.heatmapData(20, today: heatmapToday);
        final cs = Theme.of(context).colorScheme;
        final color = Color(habit.colorValue);
        final flexProgress = habit.flexProgressForDate(DateTime.now());
        final streakUnit = _localizedHabitStreakUnit(habit, locale);
        final todayLabel = habit.kind == HabitKind.negative
            ? _habitCountLabel(
                habit.todayCount(),
                habitUnit(habit, locale, habit.todayCount()),
                locale,
              )
            : habit.hasFlexRule
            ? (_localizedFlexProgressLabel(flexProgress, locale) ??
                  '${habit.todayCount()}/${habit.targetCount}')
            : '${habit.todayCount()}/${habit.targetCount}';

        final scaffold = Scaffold(
          backgroundColor: isLiquidGlass ? Colors.transparent : null,
          appBar: AppBar(
            title: Text(habit.name),
            titleTextStyle: appSecondaryRouteTitleTextStyle(context),
            actions: [
              PopupMenuButton<String>(
                tooltip: HabitUiCopy.moreActions(locale),
                onSelected: (value) async {
                  if (origin == null ||
                      !origin.isValid(context, checkCurrentRoute: true)) {
                    return;
                  }
                  if (value == 'end') {
                    await _executeEndHabit(context, habit, origin);
                  } else if (value == 'delete') {
                    await _executeDeleteHabit(context, habit, origin);
                  }
                },
                itemBuilder: (context) {
                  final cs = Theme.of(context).colorScheme;
                  return [
                    PopupMenuItem(
                      value: 'end',
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.event_busy_outlined),
                        title: Text(HabitUiCopy.endHabitAction(locale)),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.delete_outline, color: cs.error),
                        title: Text(
                          HabitUiCopy.deleteHabitAction(locale),
                          style: TextStyle(color: cs.error),
                        ),
                      ),
                    ),
                  ];
                },
              ),
              IconButton(
                tooltip: I18n.tr('action.edit'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  if (origin == null || !origin.isValid(context)) return;
                  showHabitEditor(context, habit, actionOrigin: origin);
                },
              ),
            ],
          ),
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppSurfaceCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          habitDisplayIconFor(habit),
                          color: color,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        habit.name,
                        style: appSecondaryRouteTitleTextStyle(context),
                      ),
                      if (habit.hasFlexRule) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${localizedFlexPeriodGoalLabel(habit, locale)} · ${I18n.tr('habit.daily_prefix')} ${habit.targetCount} ${habitUnit(habit, locale, habit.targetCount)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                      if (habit.startDate != null || habit.endDate != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          habitDateRangeLabel(
                            habit.startDate,
                            habit.endDate,
                            pattern: AppDateFormat.patternOf(context),
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                      if (habit.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in habit.tags)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '#$tag',
                                  style: TextStyle(fontSize: 11, color: color),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(
                                alpha: 0.55,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.ac_unit_outlined,
                                  size: 14,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  locale == AppLocale.en
                                      ? 'Rest passes: ${habit.freezeTokens}'
                                      : '休息卡: ${habit.freezeTokens} 张',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (habit.isActiveToday() &&
                              !habit.isCompletedToday() &&
                              origin != null)
                            ActionChip(
                              key: const ValueKey('habit_detail_today_freeze_btn'),
                              avatar: Icon(
                                Icons.ac_unit_outlined,
                                size: 15,
                                color: habit.isFrozenForDate(DateTime.now())
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                              label: Text(
                                habit.isFrozenForDate(DateTime.now())
                                    ? (locale == AppLocale.en
                                          ? 'Rest pass active today'
                                          : '今日已用休息卡')
                                    : (locale == AppLocale.en
                                          ? 'Use rest pass today'
                                          : '今日用休息卡保连胜'),
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () => _handleToggleFreeze(
                                context,
                                habit,
                                DateTime.now(),
                                origin,
                                locale,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _StatChip(
                            label: I18n.tr('habit.stat.current_streak'),
                            value: _habitCountWithUnit(
                              habit.currentStreak,
                              streakUnit,
                              locale,
                            ),
                          ),
                          _StatChip(
                            label: I18n.tr('habit.stat.best_streak'),
                            value: _habitCountWithUnit(
                              habit.bestStreak,
                              streakUnit,
                              locale,
                            ),
                          ),
                          _StatChip(
                            label: I18n.tr('habit.stat.today'),
                            value: todayLabel,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (habit.isEnded)
                            OutlinedButton.icon(
                              key: const ValueKey('habit_detail_reopen_btn'),
                              style: _habitDetailActionButtonStyle(context),
                              onPressed:
                                  (origin == null ||
                                      !origin.isValid(
                                        context,
                                        checkCurrentRoute: true,
                                      ))
                                  ? null
                                  : () => origin.habitProvider.reopenHabit(
                                      habit.id,
                                    ),
                              icon: const Icon(
                                Icons.replay_outlined,
                                size: 16,
                              ),
                              label: Text(
                                locale == AppLocale.en
                                    ? 'Reactivate'
                                    : '重新启用',
                              ),
                            )
                          else
                            OutlinedButton.icon(
                              style: _habitDetailActionButtonStyle(context),
                              onPressed:
                                  (origin == null ||
                                      !origin.isValid(
                                        context,
                                        checkCurrentRoute: true,
                                      ))
                                  ? null
                                  : () => _executeEndHabit(
                                      context,
                                      habit,
                                      origin,
                                    ),
                              icon: const Icon(
                                Icons.event_busy_outlined,
                                size: 16,
                              ),
                              label: Text(HabitUiCopy.endHabitAction(locale)),
                            ),
                          OutlinedButton.icon(
                            style: _habitDangerOutlinedButtonStyle(context),
                            onPressed:
                                (origin == null ||
                                    !origin.isValid(
                                      context,
                                      checkCurrentRoute: true,
                                    ))
                                ? null
                                : () => _executeDeleteHabit(
                                    context,
                                    habit,
                                    origin,
                                  ),
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: Text(HabitUiCopy.actionDelete(locale)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  I18n.tr('habit.heatmap.title'),
                  style: TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                ),
              ),
              HabitHeatmap(
                heatmapData: heatmapData,
                weeks: 20,
                today: heatmapToday,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _HabitTrendCard(habit: habit),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        I18n.tr('habit.records.title'),
                        style: TextStyle(
                          fontWeight: FontWeight.normal,
                          fontSize: 15,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('habit_detail_pick_date_backfill'),
                      onPressed: () async {
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _pickedBackfillDate ?? today,
                          firstDate: DateTime(2000),
                          lastDate: today,
                        );
                        if (picked != null && mounted) {
                          setState(
                            () => _pickedBackfillDate = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                            ),
                          );
                        }
                      },
                      icon: const Icon(
                        Icons.calendar_month_outlined,
                        size: 16,
                      ),
                      label: Text(
                        locale == AppLocale.en ? 'Pick date (>30d)' : '选日期补卡',
                      ),
                    ),
                  ],
                ),
              ),
              if (_pickedBackfillDate != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: AppSurfaceCard(
                    key: const ValueKey('habit_detail_picked_backfill_row'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: _buildDetailRecordRow(
                      context,
                      habit: habit,
                      d: _pickedBackfillDate!,
                      origin: origin,
                      locale: locale,
                      cs: cs,
                      showYearDate: true,
                      onClearPicked: () =>
                          setState(() => _pickedBackfillDate = null),
                    ),
                  ),
                ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 30,
                itemBuilder: (_, i) {
                  final d = DateTime.now().subtract(Duration(days: i));
                  final activeForDay = habit.activeForDate(d);
                  final count = habit.countForDate(d);
                  final progress = habit.progressForDate(d);
                  final completed = habit.isCompletedForDate(d);
                  final frozen = habit.isFrozenForDate(d);
                  final note = habit.noteForDate(d);
                  final unit = habitUnit(habit, locale, count);
                  final countLabel = !activeForDay
                      ? I18n.tr('habit.records.inactive')
                      : habit.kind == HabitKind.negative
                      ? _habitCountLabel(count, unit, locale)
                      : habit.hasFlexRule
                      ? localizedHabitCountForDate(habit, d, locale)
                      : '$count/${habit.targetCount}';
                  return ListTile(
                    dense: true,
                    leading: Text(
                      '${d.month}/${d.day}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    title: LinearProgressIndicator(
                      value: progress,
                      color: activeForDay
                          ? (completed ? DesignTokens.defaultSuccess : cs.error)
                          : cs.onSurfaceVariant,
                    ),
                    subtitle: (note != null || frozen)
                        ? Text(
                            [
                              if (frozen)
                                (locale == AppLocale.en
                                    ? 'Rest pass'
                                    : '休息卡'),
                              ?note,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          countLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: !activeForDay
                                ? cs.onSurfaceVariant
                                : completed
                                ? appReadableForeground(
                                    cs.surface,
                                    DesignTokens.defaultSuccess,
                                  )
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        if (count > 0 && activeForDay)
                          Tooltip(
                            message: I18n.tr('habit.records.undo_once'),
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              iconSize: 18,
                              onPressed:
                                  (origin == null ||
                                      !origin.isValid(
                                        context,
                                        checkCurrentRoute: true,
                                      ))
                                  ? null
                                  : () => _handleDateUndo(
                                      context,
                                      habit,
                                      d,
                                      origin,
                                    ),
                              icon: const Icon(Icons.undo),
                            ),
                          ),
                        Tooltip(
                          message: !activeForDay
                              ? I18n.tr('habit.records.inactive')
                              : habit.kind == HabitKind.negative
                              ? I18n.tr('habit.records.record_once')
                              : I18n.tr('habit.records.make_up_once'),
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 18,
                            onPressed:
                                (activeForDay &&
                                    origin != null &&
                                    origin.isValid(
                                      context,
                                      checkCurrentRoute: true,
                                    ))
                                ? () => _handleDateRecord(
                                    context,
                                    habit,
                                    d,
                                    origin,
                                  )
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ),
                        Tooltip(
                          message: locale == AppLocale.en
                              ? 'Reflection note'
                              : '打卡心得',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 17,
                            onPressed:
                                (origin == null ||
                                    !origin.isValid(
                                      context,
                                      checkCurrentRoute: true,
                                    ))
                                ? null
                                : () => _showReflectionNoteDialog(
                                    context,
                                    habit,
                                    d,
                                    origin,
                                    locale,
                                  ),
                            icon: Icon(
                              note != null
                                  ? Icons.sticky_note_2
                                  : Icons.edit_note_outlined,
                              color: note != null ? cs.primary : null,
                            ),
                          ),
                        ),
                        if (activeForDay && !completed)
                          Tooltip(
                            message: frozen
                                ? (locale == AppLocale.en
                                      ? 'Remove rest pass'
                                      : '取消休息卡')
                                : (locale == AppLocale.en
                                      ? 'Use rest pass'
                                      : '使用休息卡'),
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              iconSize: 17,
                              onPressed:
                                  (origin == null ||
                                      !origin.isValid(
                                        context,
                                        checkCurrentRoute: true,
                                      ))
                                  ? null
                                  : () => _handleToggleFreeze(
                                      context,
                                      habit,
                                      d,
                                      origin,
                                      locale,
                                    ),
                              icon: Icon(
                                Icons.ac_unit_outlined,
                                color: frozen ? cs.primary : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              if (habit.sortedCheckinNotes.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: AppSurfaceCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.edit_note_outlined,
                              size: 18,
                              color: color,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              locale == AppLocale.en
                                  ? 'Reflection notes'
                                  : '打卡心得记录',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final entry in habit.sortedCheckinNotes.take(10))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    entry.value,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
        return _wrapScaffold(context, scaffold);
      },
    );
  }

  Widget _buildDetailRecordRow(
    BuildContext context, {
    required Habit habit,
    required DateTime d,
    required HabitActionOrigin? origin,
    required AppLocale locale,
    required ColorScheme cs,
    bool showYearDate = false,
    VoidCallback? onClearPicked,
  }) {
    final activeForDay = habit.activeForDate(d);
    final count = habit.countForDate(d);
    final progress = habit.progressForDate(d);
    final completed = habit.isCompletedForDate(d);
    final frozen = habit.isFrozenForDate(d);
    final note = habit.noteForDate(d);
    final unit = habitUnit(habit, locale, count);
    final countLabel = !activeForDay
        ? I18n.tr('habit.records.inactive')
        : habit.kind == HabitKind.negative
        ? _habitCountLabel(count, unit, locale)
        : habit.hasFlexRule
        ? localizedHabitCountForDate(habit, d, locale)
        : '$count/${habit.targetCount}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                showYearDate
                    ? AppDateFormat.date(context, d)
                    : '${d.month}/${d.day}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Text(
              countLabel,
              style: TextStyle(
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: !activeForDay
                    ? cs.onSurfaceVariant
                    : completed
                    ? appReadableForeground(
                        cs.surface,
                        DesignTokens.defaultSuccess,
                      )
                    : cs.onSurfaceVariant,
              ),
            ),
            if (onClearPicked != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: onClearPicked,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: progress,
          color: activeForDay
              ? (completed ? DesignTokens.defaultSuccess : cs.error)
              : cs.onSurfaceVariant,
        ),
        if (note != null || frozen) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (frozen) (locale == AppLocale.en ? 'Rest pass' : '休息卡'),
              ?note,
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (count > 0 && activeForDay)
              ActionChip(
                avatar: const Icon(Icons.undo, size: 15),
                label: Text(I18n.tr('habit.records.undo_once')),
                onPressed:
                    (origin == null ||
                        !origin.isValid(context, checkCurrentRoute: true))
                    ? null
                    : () => _handleDateUndo(context, habit, d, origin),
              ),
            ActionChip(
              avatar: const Icon(Icons.add_circle_outline, size: 15),
              label: Text(
                !activeForDay
                    ? I18n.tr('habit.records.inactive')
                    : habit.kind == HabitKind.negative
                    ? I18n.tr('habit.records.record_once')
                    : I18n.tr('habit.records.make_up_once'),
              ),
              onPressed:
                  (activeForDay &&
                      origin != null &&
                      origin.isValid(context, checkCurrentRoute: true))
                  ? () => _handleDateRecord(context, habit, d, origin)
                  : null,
            ),
            ActionChip(
              avatar: const Icon(Icons.edit_note_outlined, size: 15),
              label: Text(
                locale == AppLocale.en ? 'Reflection' : '写心得',
              ),
              onPressed:
                  (origin == null ||
                      !origin.isValid(context, checkCurrentRoute: true))
                  ? null
                  : () => _showReflectionNoteDialog(
                      context,
                      habit,
                      d,
                      origin,
                      locale,
                    ),
            ),
            if (activeForDay && !completed)
              ActionChip(
                avatar: const Icon(Icons.ac_unit_outlined, size: 15),
                label: Text(
                  frozen
                      ? (locale == AppLocale.en ? 'Remove rest pass' : '取消休息卡')
                      : (locale == AppLocale.en ? 'Rest pass' : '使用休息卡'),
                ),
                onPressed:
                    (origin == null ||
                        !origin.isValid(context, checkCurrentRoute: true))
                    ? null
                    : () => _handleToggleFreeze(
                        context,
                        habit,
                        d,
                        origin,
                        locale,
                      ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _handleToggleFreeze(
    BuildContext context,
    Habit habit,
    DateTime date,
    HabitActionOrigin origin,
    AppLocale locale,
  ) async {
    if (!origin.isValid(context, checkCurrentRoute: true)) return;
    final ok = await origin.habitProvider.toggleStreakFreezeForDate(
      habit.id,
      date,
    );
    if (!context.mounted || !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    if (!ok) {
      showHabitSafeFeedback(
        context,
        (loc) => loc == AppLocale.en
            ? 'No rest passes left or date already complete'
            : '当前没有可用休息卡或当日已达标',
        origin: origin,
      );
    }
  }

  Future<void> _showReflectionNoteDialog(
    BuildContext context,
    Habit habit,
    DateTime date,
    HabitActionOrigin origin,
    AppLocale locale,
  ) async {
    if (!origin.isValid(context, checkCurrentRoute: true)) return;
    final ctrl = TextEditingController(text: habit.noteForDate(date) ?? '');
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AppDialog(
          title: Text(
            locale == AppLocale.en
                ? 'Reflection (${AppDateFormat.date(ctx, date)})'
                : '打卡心得 (${AppDateFormat.date(ctx, date)})',
          ),
          content: TextField(
            controller: ctrl,
            maxLines: 4,
            autofocus: true,
            decoration: InputDecoration(
              hintText: locale == AppLocale.en
                  ? 'Write how this check-in felt...'
                  : '记录本次打卡的感受、收获或阻滞…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: Text(I18n.tr('action.save')),
            ),
          ],
        ),
      );
      if (result == null ||
          !context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      await origin.habitProvider.setHabitCheckinNote(habit.id, date, result);
    } finally {
      ctrl.dispose();
    }
  }
}

class _HabitTrendCard extends StatefulWidget {
  final Habit habit;

  const _HabitTrendCard({required this.habit});

  @override
  State<_HabitTrendCard> createState() => _HabitTrendCardState();
}

class _HabitTrendCardState extends State<_HabitTrendCard> {
  HabitTrendWindow _window = HabitTrendWindow.days30;

  @override
  Widget build(BuildContext context) {
    final summary = buildHabitTrendSummary(widget.habit, window: _window);
    final cs = Theme.of(context).colorScheme;
    final color = Color(widget.habit.colorValue);
    final unit = habitUnit(widget.habit, I18n.current, summary.averageCount);
    final trendColor = _directionColor(summary.direction, cs);
    final delta = (summary.completionRateDelta * 100).round();

    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  I18n.tr('habit.trend.title'),
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '${(summary.completionRate * 100).round()}%',
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final labelStyle = Theme.of(context).textTheme.labelLarge!
                  .copyWith(fontSize: 12, fontWeight: FontWeight.normal);
              final direction = Directionality.of(context);
              final padding = SegmentedButtonTheme.of(context).style?.padding
                  ?.resolve(const <WidgetState>{})
                  ?.resolve(direction);
              var segmentWidth = 0.0;
              for (final window in HabitTrendWindow.values) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: localizedHabitTrendWindowLabel(window),
                    style: labelStyle,
                  ),
                  textDirection: direction,
                  textScaler: MediaQuery.textScalerOf(context),
                  locale: Localizations.maybeLocaleOf(context),
                )..layout();
                final width =
                    painter.width.ceilToDouble() + (padding?.horizontal ?? 24);
                if (width > segmentWidth) segmentWidth = width;
                painter.dispose();
              }
              return SegmentedButton<HabitTrendWindow>(
                direction:
                    segmentWidth * HabitTrendWindow.values.length <=
                        constraints.maxWidth
                    ? Axis.horizontal
                    : Axis.vertical,
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: WidgetStateProperty.all(labelStyle),
                ),
                segments: [
                  for (final window in HabitTrendWindow.values)
                    ButtonSegment(
                      value: window,
                      label: Text(localizedHabitTrendWindowLabel(window)),
                    ),
                ],
                selected: {_window},
                onSelectionChanged: (value) {
                  setState(() => _window = value.first);
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HabitTrendMetric(
                label: I18n.tr('habit.trend.completed'),
                value: '${summary.completedDays}/${summary.activeDays}',
              ),
              _HabitTrendMetric(
                label: I18n.tr('habit.trend.daily_average'),
                value: '${summary.averageCount.toStringAsFixed(1)} $unit',
              ),
              _HabitTrendMetric(
                label: I18n.tr('habit.trend.longest_streak'),
                value:
                    '${summary.longestCompletedStreak} ${I18n.tr('unit.day')}',
              ),
              _HabitTrendMetric(
                label: I18n.tr('habit.trend.vs_previous'),
                value: delta == 0
                    ? I18n.tr('today.productivity.flat')
                    : '${delta > 0 ? '+' : ''}$delta%',
                color: trendColor,
                icon: _directionIcon(summary.direction),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            I18n.tr('habit.trend.bucket_details'),
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 8),
          for (final bucket in summary.buckets)
            _HabitTrendBucketRow(
              bucket: bucket,
              color: color,
              errorColor: cs.error,
              unit: habitUnit(widget.habit, I18n.current, bucket.totalCount),
            ),
        ],
      ),
    );
  }
}

class _HabitTrendMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  const _HabitTrendMetric({
    required this.label,
    required this.value,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = color ?? cs.onSurface;
    return Container(
      constraints: const BoxConstraints(minWidth: 88),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: effectiveColor),
                const SizedBox(width: 3),
              ],
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  color: effectiveColor,
                  fontWeight: FontWeight.normal,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HabitTrendBucketRow extends StatelessWidget {
  final HabitTrendBucket bucket;
  final Color color;
  final Color errorColor;
  final String unit;

  const _HabitTrendBucketRow({
    required this.bucket,
    required this.color,
    required this.errorColor,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rate = bucket.completionRate;
    final rowColor = rate >= 0.5 ? color : errorColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const labelStyle = TextStyle(fontSize: 11);
          final valueStyle = TextStyle(
            fontSize: 11,
            color: bucket.completedDays > 0 ? rowColor : cs.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          );
          final value =
              '${bucket.completedDays}/${bucket.activeDays} · ${bucket.totalCount} $unit';
          double naturalWidth(String text, TextStyle style) {
            final painter = TextPainter(
              text: TextSpan(
                text: text,
                style: DefaultTextStyle.of(context).style.merge(style),
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              locale: Localizations.maybeLocaleOf(context),
            )..layout();
            final width = painter.width.ceilToDouble();
            painter.dispose();
            return width;
          }

          final labelWidth = naturalWidth(bucket.label, labelStyle);
          final valueWidth = naturalWidth(value, valueStyle);
          final bar = ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(height: 8, color: color.withValues(alpha: 0.10)),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 8,
                      width: constraints.maxWidth * rate,
                      color: rowColor,
                    ),
                  ],
                );
              },
            ),
          );
          if (labelWidth + valueWidth + 16 + 48 <= constraints.maxWidth) {
            return Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(bucket.label, style: labelStyle),
                ),
                const SizedBox(width: 8),
                Expanded(child: bar),
                const SizedBox(width: 8),
                SizedBox(
                  width: valueWidth,
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: valueStyle,
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(bucket.label, style: labelStyle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: valueStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              bar,
            ],
          );
        },
      ),
    );
  }
}

Color _directionColor(HabitTrendDirection direction, ColorScheme cs) {
  return switch (direction) {
    HabitTrendDirection.up => appReadableForeground(
      cs.surface,
      DesignTokens.defaultSuccess,
    ),
    HabitTrendDirection.down => cs.error,
    HabitTrendDirection.flat => cs.onSurfaceVariant,
  };
}

IconData _directionIcon(HabitTrendDirection direction) {
  return switch (direction) {
    HabitTrendDirection.up => Icons.trending_up,
    HabitTrendDirection.down => Icons.trending_down,
    HabitTrendDirection.flat => Icons.trending_flat,
  };
}

Future<void> _openSystemSettings(
  BuildContext context, {
  HabitActionOrigin? origin,
}) async {
  final route = ModalRoute.of(context);
  if (origin != null && !origin.isValid(context, specificRoute: route)) return;
  final opened = await openAppSettings();
  if (!context.mounted ||
      (origin != null && !origin.isValid(context, specificRoute: route))) {
    return;
  }
  if (!opened) {
    showHabitSafeFeedback(
      context,
      (locale) =>
          I18n.trForLocale('preferences.notify.open_settings_failed', locale),
      origin: origin,
      route: route,
    );
  }
}

String habitUnit(Habit habit, [AppLocale? locale, num? count]) =>
    HabitUiCopy.measurementUnit(
      count ?? habit.targetCount,
      authoredUnit: habit.unit,
      generatedUnitKey: habit.generatedUnitKey,
      locale: locale,
    );

String localizedFlexPeriodGoalLabel(Habit habit, [AppLocale? locale]) {
  if (!habit.hasFlexRule) return '';
  final copy = HabitUiCopy(locale ?? I18n.current);
  return switch (habit.flexPeriod!) {
    HabitFlexPeriod.week => copy.weekGoal(habit.effectiveFlexTarget),
    HabitFlexPeriod.month => copy.monthGoal(habit.effectiveFlexTarget),
  };
}

String? _localizedFlexProgressLabel(
  HabitFlexProgress? progress, [
  AppLocale? locale,
]) {
  if (progress == null) return null;
  final prefix = switch (progress.period) {
    HabitFlexPeriod.week => I18n.trForLocale(
      'habit.flex.this_week',
      locale ?? I18n.current,
    ),
    HabitFlexPeriod.month => I18n.trForLocale(
      'habit.flex.this_month',
      locale ?? I18n.current,
    ),
  };
  return '$prefix ${progress.completed}/${progress.target}';
}

String localizedHabitCountForDate(
  Habit habit,
  DateTime date, [
  AppLocale? locale,
]) {
  final count = habit.countForDate(date);
  final unit = habitUnit(habit, locale, count);
  final targetUnit = habitUnit(habit, locale, habit.targetCount);
  if (habit.hasFlexRule) {
    final progress = _localizedFlexProgressLabel(
      habit.flexProgressForDate(date),
      locale,
    );
    return progress == null
        ? _habitCountLabel(count, unit, locale)
        : '${_habitCountLabel(count, unit, locale)} · $progress';
  }
  return habit.kind == HabitKind.positive
      ? '$count $unit / ${habit.targetCount} $targetUnit'
      : _habitCountLabel(count, unit, locale);
}

String localizedHabitTrendWindowLabel(HabitTrendWindow window) {
  return switch (window) {
    HabitTrendWindow.days14 => _habitCountWithUnit('14', I18n.tr('unit.day')),
    HabitTrendWindow.days30 => _habitCountWithUnit('30', I18n.tr('unit.day')),
    HabitTrendWindow.days90 => _habitCountWithUnit('90', I18n.tr('unit.day')),
    HabitTrendWindow.days365 => I18n.tr('habit.trend.one_year'),
  };
}

/// 数字与单位拼接：zh 习惯紧拼（「5天」「14天」），en 单位是独立单词需要
/// 空格（「5 days」「14 days」）。共享 unit 词条（unit.day 等）同时服务
/// 已带空格的拼接点（如 '${count} ${unit}'），不能在值里内置前导空格，
/// 因此空格在此处按语言补齐。
String _habitCountWithUnit(Object count, String unit, [AppLocale? locale]) {
  if (unit.isEmpty) return '$count';
  final spaced =
      (locale ?? I18n.current) == AppLocale.en && !unit.startsWith(' ');
  return spaced ? '$count $unit' : '$count$unit';
}

String _localizedHabitStreakUnit(Habit habit, [AppLocale? locale]) {
  String text(String key) => I18n.trForLocale(key, locale ?? I18n.current);
  if (!habit.hasFlexRule) return text('unit.day');
  return switch (habit.flexPeriod!) {
    HabitFlexPeriod.week => text('habit.unit.week'),
    HabitFlexPeriod.month => text('habit.unit.month'),
  };
}

String _habitCountLabel(int count, String unit, [AppLocale? locale]) {
  return '${I18n.trForLocale('habit.recorded_prefix', locale ?? I18n.current)}$count $unit';
}

ReminderPlan _habitReminderPlan(Habit habit) {
  if (habit.reminderPlan.enabled && habit.reminderPlan.rules.isNotEmpty) {
    return _normalizeHabitReminderPlan(habit.reminderPlan);
  }
  if (!habit.remind || habit.remindHour == null || habit.remindMinute == null) {
    return const ReminderPlan.disabled();
  }
  final weekdays =
      habit.activeWeekdays
          .where((d) => d >= 0 && d <= 6)
          .map((d) => d + 1)
          .toList()
        ..sort();
  final fullWeek = weekdays.length == 7;
  return ReminderPlan(
    enabled: true,
    rules: [
      ReminderRule(
        id: 'habit-reminder',
        enabled: true,
        type: fullWeek
            ? ReminderRuleType.dailyTime
            : ReminderRuleType.weeklyTime,
        kind: ReminderKind.popup,
        hour: habit.remindHour,
        minute: habit.remindMinute,
        weekdays: fullWeek ? const <int>[] : weekdays,
      ),
    ],
  );
}

/// 编辑表单当前是否配置了"每周某几天"的提醒，用于提示生效星期独立。
bool _habitPlanHasWeeklyReminder(ReminderPlan plan) {
  return plan.rules.any(
    (rule) => rule.enabled && rule.type == ReminderRuleType.weeklyTime,
  );
}

ReminderPlan _normalizeHabitReminderPlan(ReminderPlan plan) {
  final rules = plan.rules.map(_normalizeHabitReminderRule).toList();
  return ReminderPlan(enabled: plan.enabled, rules: rules);
}

ReminderRule _normalizeHabitReminderRule(ReminderRule rule) {
  var type = rule.type;
  var weekdays = rule.weekdays;
  if (type == ReminderRuleType.absolute ||
      type == ReminderRuleType.relativeToDue) {
    type = ReminderRuleType.dailyTime;
    weekdays = const <int>[];
  } else if (type == ReminderRuleType.weeklyTime) {
    weekdays =
        rule.weekdays.where((day) => day >= 1 && day <= 7).toSet().toList()
          ..sort();
    if (weekdays.isEmpty) type = ReminderRuleType.dailyTime;
  } else {
    weekdays = const <int>[];
  }

  return rule.copyWith(
    type: type,
    kind: ReminderKind.popup,
    weekdays: weekdays,
    fullScreen: false,
    snoozeMinutes: 0,
    repeatCount: 0,
  );
}

List<ReminderRule> _activeHabitReminderRules(ReminderPlan plan) {
  if (!plan.enabled) return const <ReminderRule>[];
  final rules = <ReminderRule>[];
  for (final rule in plan.rules) {
    if (!rule.enabled || rule.kind == ReminderKind.off) continue;
    if (rule.hour == null || rule.minute == null) continue;
    rules.add(_normalizeHabitReminderRule(rule));
  }
  return rules;
}

ReminderRule? _habitPrimaryReminder(ReminderPlan plan) {
  final activeRules = _activeHabitReminderRules(plan);
  if (activeRules.isNotEmpty) return activeRules.first;
  return plan.rules.isEmpty
      ? null
      : _normalizeHabitReminderRule(plan.rules.first);
}

DateTime? _nextHabitReminderTriggerForPlan(List<ReminderRule> rules) {
  DateTime? next;
  for (final rule in rules) {
    final trigger = _nextHabitReminderTrigger(rule);
    if (trigger == null) continue;
    if (next == null || trigger.isBefore(next)) next = trigger;
  }
  return next;
}

DateTime? _nextHabitReminderTrigger(ReminderRule rule) {
  final hour = rule.hour;
  final minute = rule.minute;
  if (hour == null || minute == null) return null;
  final now = DateTime.now();
  final weekdays = rule.type == ReminderRuleType.weeklyTime
      ? rule.weekdays.where((day) => day >= 1 && day <= 7).toSet()
      : const <int>{};
  for (var offset = 0; offset <= 7; offset++) {
    final date = now.add(Duration(days: offset));
    final target = DateTime(date.year, date.month, date.day, hour, minute);
    if (!target.isAfter(now)) continue;
    if (weekdays.isNotEmpty && !weekdays.contains(target.weekday)) continue;
    return target;
  }
  return null;
}

bool _habitHasReminder(Habit habit) {
  return habit.remind ||
      (habit.remindHour != null && habit.remindMinute != null) ||
      (habit.reminderPlan.enabled && habit.reminderPlan.rules.isNotEmpty);
}

String _habitReminderSyncIssueText(String issue, [AppLocale? locale]) {
  if (issue == 'reminder_scheduler_missing') {
    return HabitUiCopy.reminderSchedulerMissing(locale);
  }
  return issue;
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 78),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 16,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
