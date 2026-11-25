import '../widgets/app_date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import '../core/ai_schedule_ui_copy.dart';
import '../core/design_tokens.dart' show DesignTokens;
import '../core/i18n.dart';
import '../models/calendar_event.dart';
import '../models/goal.dart' show ReminderKind;
import '../providers/auth_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/cloud_sync_provider.dart';
import '../providers/notification_service.dart';
import '../providers/todo_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/ai_service.dart';
import '../services/local_notifications.dart';
import '../services/reminder_issue_copy.dart' show NotificationIssueTitle;
import '../services/reminder_scheduler.dart';
import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;
import '../widgets/surface_components.dart';
import 'goal_edit_screen.dart';

class AiScheduleScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final String initialText;
  final DateTime? initialDate;

  const AiScheduleScreen({super.key, this.initialText = '', this.initialDate});

  @override
  State<AiScheduleScreen> createState() => _AiScheduleScreenState();
}

class _CreationOutcome {
  final bool isCalendar;
  final String title;
  final DateTime startAt;
  final bool reminderFailed;
  final String Function([AppLocale? locale])? reminderStatusBuilder;
  final int accountGeneration;
  final String? userId;

  const _CreationOutcome({
    required this.isCalendar,
    required this.title,
    required this.startAt,
    required this.reminderFailed,
    this.reminderStatusBuilder,
    required this.accountGeneration,
    this.userId,
  });
}

class _AiScheduleScreenState extends State<AiScheduleScreen> {
  late final TextEditingController _inputCtrl;
  late final FocusNode _inputFocusNode;
  AiScheduleDraft? _draft;
  String? _draftSourceInput;
  int _recognizeRequestId = 0;
  bool _loading = false;
  bool _saving = false;
  String Function()? _errorBuilder;

  bool _originRevoked = false;
  bool _disposed = false;
  bool _cleanupScheduled = false;
  bool _intentInitialized = false;
  AuthProvider? _initialAuth;
  String? _initialUserId;
  bool _initialIsLoggedIn = false;
  AuthSessionLease? _initialSessionLease;
  int _initialAccountGeneration = 0;
  ModalRoute<dynamic>? _route;

  _CreationOutcome? _creationOutcome;
  DialogRoute<void>? _completionDialogRoute;

  @override
  void initState() {
    super.initState();
    _inputCtrl = TextEditingController(text: widget.initialText);
    _inputFocusNode = FocusNode();
    I18n.localeListenable.addListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountDataGenerationChanged,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentAuth = _observeAuthProvider();
    if (!_intentInitialized) {
      _intentInitialized = true;
      _route = ModalRoute.of(context);
      _initialAccountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      _initialAuth = currentAuth;
      if (currentAuth != null) {
        _initialUserId = currentAuth.state.userId;
        _initialIsLoggedIn = currentAuth.state.isLoggedIn;
        if (currentAuth.state.isLoggedIn) {
          try {
            _initialSessionLease = currentAuth.captureSessionLease();
          } catch (_) {
            _initialSessionLease = null;
          }
        }
        currentAuth.addListener(_onAuthChanged);
      }
    } else {
      if (!identical(currentAuth, _initialAuth)) {
        _handleAccountInvalidated();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final dialogRoute = _completionDialogRoute;
    _completionDialogRoute = null;
    _detachAndRemoveDialogRoute(dialogRoute);

    _initialAuth?.removeListener(_onAuthChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountDataGenerationChanged,
    );
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _inputFocusNode.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  void _onLocaleChanged() {
    _safeSetState(() {});
  }

  void _onAuthChanged() {
    if (!mounted || _disposed) return;
    if (_initialUserId == null && _initialAuth?.state.userId != null) {
      _initialUserId = _initialAuth?.state.userId;
    }
    if (!_isCurrentAccountIntent()) {
      _handleAccountInvalidated();
    }
  }

  void _onAccountDataGenerationChanged() {
    if (!mounted || _disposed) return;
    if (!_isCurrentAccountIntent()) {
      _handleAccountInvalidated();
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted || _disposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        WidgetsBinding.instance.buildOwner?.debugBuilding == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  void _handleAccountInvalidated() {
    _originRevoked = true;
    _draft = null;
    _draftSourceInput = null;
    _creationOutcome = null;
    _loading = false;
    _saving = false;
    _errorBuilder = () => AiScheduleUiCopy.accountChanged;

    final dialogRoute = _completionDialogRoute;
    _completionDialogRoute = null;
    _detachAndRemoveDialogRoute(dialogRoute);

    _scheduleOrPerformLiveOriginCleanup();
  }

  void _detachAndRemoveDialogRoute(DialogRoute<void>? route) {
    if (route == null) return;
    void doRemove() {
      if (route.isActive && route.navigator?.mounted == true) {
        route.navigator!.removeRoute(route);
      }
    }

    // Navigator can also be locked during an idle-phase push notification.
    // Remove our captured route after that transition, even if its owner has
    // already been disposed. No BuildContext or owner State is needed here.
    WidgetsBinding.instance.addPostFrameCallback((_) => doRemove());
    WidgetsBinding.instance.scheduleFrame();
  }

  void _scheduleOrPerformLiveOriginCleanup() {
    if (_disposed || !mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final isBuildingOrLocked =
        phase == SchedulerPhase.persistentCallbacks ||
        WidgetsBinding.instance.buildOwner?.debugBuilding == true;

    if (isBuildingOrLocked) {
      if (!_cleanupScheduled) {
        _cleanupScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _cleanupScheduled = false;
          if (_disposed || !mounted) return;
          _inputCtrl.clear();
          setState(() {});
        });
      }
    } else {
      _inputCtrl.clear();
      setState(() {});
    }
  }

  bool Function() _captureOriginGuard() {
    final initialAuth = _initialAuth;
    final initialUserId = _initialUserId;
    final initialIsLoggedIn = _initialIsLoggedIn;
    final initialSessionLease = _initialSessionLease;
    final initialAccountGeneration = _initialAccountGeneration;

    return () {
      if (_originRevoked) {
        return false;
      }
      if (initialIsLoggedIn && initialSessionLease == null) {
        return false;
      }
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            initialAccountGeneration,
          ) ||
          initialAccountGeneration !=
              AccountLocalDataCleaner.accountDataGeneration) {
        return false;
      }
      if (initialAuth != null) {
        if (initialUserId != null && initialUserId.isNotEmpty) {
          if (initialAuth.state.userId != initialUserId) {
            return false;
          }
        }
        if (initialAuth.state.isLoggedIn != initialIsLoggedIn) {
          return false;
        }
        if (initialIsLoggedIn) {
          if (initialSessionLease == null ||
              !initialAuth.isSessionLeaseCurrent(initialSessionLease)) {
            return false;
          }
        }
        if (initialAuth.isAccountTransitionInProgress ||
            initialAuth.isLocalAccountDataBlocked) {
          return false;
        }
      }
      return true;
    };
  }

  AuthProvider? _observeAuthProvider() {
    try {
      return Provider.of<AuthProvider>(context, listen: true);
    } on ProviderNotFoundException {
      return null;
    }
  }

  AuthProvider? _peekCurrentAuthProvider() {
    try {
      return Provider.of<AuthProvider>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  bool _isCurrentAccountIntent() {
    if (_originRevoked) {
      return false;
    }
    if (_initialIsLoggedIn && _initialSessionLease == null) {
      return false;
    }
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _initialAccountGeneration,
        ) ||
        _initialAccountGeneration !=
            AccountLocalDataCleaner.accountDataGeneration) {
      return false;
    }
    if (mounted && !_disposed) {
      final currentAuth = _peekCurrentAuthProvider();
      if (_initialAuth != null) {
        if (currentAuth == null || !identical(currentAuth, _initialAuth)) {
          return false;
        }
      } else if (currentAuth != null) {
        return false;
      }
    }
    final auth = _initialAuth;
    if (auth != null) {
      if (_initialUserId != null && _initialUserId!.isNotEmpty) {
        if (auth.state.userId != _initialUserId) {
          return false;
        }
      }
      if (auth.state.isLoggedIn != _initialIsLoggedIn) {
        return false;
      }
      if (_initialIsLoggedIn) {
        if (_initialSessionLease == null ||
            !auth.isSessionLeaseCurrent(_initialSessionLease!)) {
          return false;
        }
      }
      if (auth.isAccountTransitionInProgress ||
          auth.isLocalAccountDataBlocked) {
        return false;
      }
    } else if (mounted && !_disposed) {
      final currentAuth = _peekCurrentAuthProvider();
      if (currentAuth != null && currentAuth.state.isLoggedIn) {
        return false;
      }
    }
    return true;
  }

  Future<void> _recognize() async {
    if (_loading || _saving) return;
    final input = _inputCtrl.text.trim();
    final route = _route ?? ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (!_isCurrentAccountIntent()) {
      _handleAccountInvalidated();
      return;
    }
    if (input.isEmpty) {
      _safeSetState(() {
        if (_disposed || !mounted) return;
        _errorBuilder = () => AiScheduleUiCopy.emptyInput;
      });
      return;
    }
    if (_creationOutcome != null) {
      if (_draftSourceInput == input) {
        _showCompletionDialog(_creationOutcome!);
        return;
      }
      _creationOutcome = null;
    }
    _inputFocusNode.unfocus();
    final requestId = ++_recognizeRequestId;
    _safeSetState(() {
      if (_disposed || !mounted) return;
      _loading = true;
      _errorBuilder = null;
      _draft = null;
      _draftSourceInput = null;
    });
    try {
      final draft = await context.read<AiService>().createScheduleDraft(
        input,
        now: widget.initialDate,
      );
      if (!mounted) return;
      if (requestId != _recognizeRequestId ||
          !_isCurrentAccountIntent() ||
          (route != null && !route.isCurrent) ||
          _inputCtrl.text.trim() != input) {
        return;
      }
      _safeSetState(() {
        if (_disposed || !mounted) return;
        if (requestId != _recognizeRequestId ||
            !_isCurrentAccountIntent() ||
            (route != null && !route.isCurrent) ||
            _inputCtrl.text.trim() != input) {
          return;
        }
        _draft = draft;
        _draftSourceInput = input;
      });
    } on AiScheduleDiscardedException {
      if (mounted &&
          requestId == _recognizeRequestId &&
          _isCurrentAccountIntent() &&
          (route == null || route.isCurrent)) {
        _safeSetState(() {
          if (_disposed || !mounted) return;
          if (requestId != _recognizeRequestId || !_isCurrentAccountIntent()) {
            return;
          }
          _draft = null;
          _errorBuilder = () => AiScheduleUiCopy.accountChanged;
        });
      }
    } catch (e) {
      if (mounted &&
          requestId == _recognizeRequestId &&
          _isCurrentAccountIntent() &&
          (route == null || route.isCurrent)) {
        _safeSetState(() {
          if (_disposed || !mounted) return;
          if (requestId != _recognizeRequestId || !_isCurrentAccountIntent()) {
            return;
          }
          _errorBuilder = () => AiScheduleUiCopy.recognizeError(e);
        });
      }
    } finally {
      if (mounted && requestId == _recognizeRequestId) {
        _safeSetState(() {
          if (_disposed || !mounted) return;
          if (requestId == _recognizeRequestId) {
            _loading = false;
          }
        });
      }
    }
  }

  Future<void> _create() async {
    if (_saving || _loading) return;
    if (_creationOutcome != null) {
      _showCompletionDialog(_creationOutcome!);
      return;
    }
    final draft = _draft;
    if (draft == null) return;
    final route = _route ?? ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (!_isCurrentAccountIntent()) {
      _handleAccountInvalidated();
      return;
    }
    if (_draftSourceInput != _inputCtrl.text.trim()) {
      _safeSetState(() {
        if (_disposed || !mounted) return;
        _errorBuilder = () => AiScheduleUiCopy.inputChanged;
      });
      return;
    }

    final calendarProvider = context.read<CalendarProvider>();
    final todoProvider = context.read<TodoProvider>();
    final notificationService = context.read<NotificationService>();
    final originGuard = _captureOriginGuard();
    bool canContinuePreflight() =>
        mounted && (route == null || route.isCurrent) && originGuard();

    _safeSetState(() {
      if (_disposed || !mounted) return;
      _saving = true;
      _errorBuilder = null;
    });

    String Function([AppLocale? locale])? reminderStatusBuilder;
    var reminderFailed = false;
    _CreationOutcome? outcome;

    try {
      if (draft.isCalendar) {
        final event = _toCalendarEvent(draft);
        if (draft.reminderEnabled) {
          final ready = await notificationService.ensureReadyForReminder(
            scheduledTime: draft.startAt,
            issueTitle: AiScheduleUiCopy.eventReminderIssueTitle,
            issueTitleCode: NotificationIssueTitle.aiRegistrationFailed,
            relatedId: event.id,
            canContinue: canContinuePreflight,
          );
          if (!mounted ||
              !_isCurrentAccountIntent() ||
              (route != null && !route.isCurrent)) {
            return;
          }
          if (!ready) {
            final issue = notificationService.lastScheduleIssue;
            _safeSetState(() {
              if (_disposed || !mounted) return;
              if (!_isCurrentAccountIntent()) return;
              _errorBuilder = () =>
                  AiScheduleUiCopy.renderReminderIssue(issue, I18n.current);
            });
            return;
          }
        }
        if (!mounted ||
            !_isCurrentAccountIntent() ||
            (route != null && !route.isCurrent)) {
          return;
        }
        await calendarProvider.addLocalEvent(event, canWrite: originGuard);
        if (!mounted || !_isCurrentAccountIntent()) return;
        final persisted = calendarProvider.localEvents.any(
          (e) => e.id == event.id,
        );
        if (!persisted) {
          _safeSetState(() {
            if (_disposed || !mounted) return;
            if (!_isCurrentAccountIntent()) return;
            _errorBuilder = () => AiScheduleUiCopy.genericSaveFailed;
          });
          return;
        }

        if (draft.reminderEnabled) {
          final startLocal = draft.startAt.toLocal();
          final dateParam =
              '${startLocal.year.toString().padLeft(4, '0')}-'
              '${startLocal.month.toString().padLeft(2, '0')}-'
              '${startLocal.day.toString().padLeft(2, '0')}';
          final eventPayload =
              'duoyi://calendar?date=$dateParam&eventId=${Uri.encodeComponent(event.id)}';
          try {
            await notificationService.scheduleCalendarReminder(
              calendarEventId: event.id,
              title: AiScheduleUiCopy.calendarReminderTitle,
              body: draft.title,
              when: draft.startAt,
              payload: eventPayload,
              canContinue: originGuard,
            );
            if (!mounted || !_isCurrentAccountIntent()) return;
            reminderStatusBuilder = ([loc]) =>
                AiScheduleUiCopy.reminderRegistered;
          } catch (e) {
            reminderFailed = true;
            reminderStatusBuilder = ([loc]) =>
                AiScheduleUiCopy.renderReminderIssue(e, loc);
          }
        }
        if (!mounted || !_isCurrentAccountIntent()) return;
        outcome = _CreationOutcome(
          isCalendar: true,
          title: draft.title,
          startAt: draft.startAt,
          reminderFailed: reminderFailed,
          reminderStatusBuilder: reminderStatusBuilder,
          accountGeneration: _initialAccountGeneration,
          userId: _initialUserId,
        );
        _safeSetState(() {
          if (_disposed || !mounted) return;
          if (!_isCurrentAccountIntent()) return;
          _creationOutcome = outcome;
        });
      } else {
        final todo = draft.toTodo();
        if (draft.reminderEnabled) {
          final preflight = preflightTodoReminderPlan(todo);
          final blockingIssue = preflight.blockingIssue;
          if (blockingIssue != null) {
            if (!mounted) return;
            _safeSetState(() {
              if (_disposed || !mounted) return;
              if (!_isCurrentAccountIntent()) return;
              _errorBuilder = () => AiScheduleUiCopy.renderReminderIssue(
                blockingIssue,
                I18n.current,
              );
            });
            return;
          }
          final usesPush = preflight.kinds.contains(ReminderKind.push);
          final usesPopup = preflight.kinds.contains(ReminderKind.popup);
          final usesAlarm = preflight.kinds.contains(ReminderKind.alarm);
          if (usesPush || usesPopup) {
            final ready = await notificationService.ensureReadyForReminder(
              scheduledTime: preflight.firstScheduledTime ?? draft.startAt,
              issueTitle: AiScheduleUiCopy.taskReminderIssueTitle,
              issueTitleCode: NotificationIssueTitle.aiRegistrationFailed,
              relatedId: todo.id,
              canContinue: canContinuePreflight,
            );
            if (!mounted ||
                !_isCurrentAccountIntent() ||
                (route != null && !route.isCurrent)) {
              return;
            }
            if (!ready) {
              final issue = notificationService.lastScheduleIssue;
              _safeSetState(() {
                if (_disposed || !mounted) return;
                if (!_isCurrentAccountIntent()) return;
                _errorBuilder = () =>
                    AiScheduleUiCopy.renderReminderIssue(issue, I18n.current);
              });
              return;
            }
          }
          final usesAlarmOnly = usesAlarm && !usesPush && !usesPopup;
          if (usesAlarmOnly) {
            final hasPermission = await LocalNotifications.instance
                .ensurePermission();
            if (!mounted ||
                !_isCurrentAccountIntent() ||
                (route != null && !route.isCurrent)) {
              return;
            }
            if (!hasPermission) {
              _safeSetState(() {
                if (_disposed || !mounted) return;
                if (!_isCurrentAccountIntent()) return;
                _errorBuilder = () => AiScheduleUiCopy.alarmPermissionRequired;
              });
              return;
            }
          }
        }
        if (!mounted ||
            !_isCurrentAccountIntent() ||
            (route != null && !route.isCurrent)) {
          return;
        }
        if (draft.reminderEnabled) {
          notificationService.clearScheduleIssue();
          final reminderSyncResult = await todoProvider.addTodoWithResult(
            todo,
            waitForReminderSync: true,
            reportReminderScheduleFailure: true,
            canWrite: originGuard,
          );
          if (!mounted || !_isCurrentAccountIntent()) return;
          if (reminderSyncResult == null) {
            _safeSetState(() {
              if (_disposed || !mounted) return;
              if (!_isCurrentAccountIntent()) return;
              _errorBuilder = () => AiScheduleUiCopy.genericSaveFailed;
            });
            return;
          }
          if (reminderSyncResult.hasIssue) {
            reminderFailed = true;
            reminderStatusBuilder = ([loc]) =>
                AiScheduleUiCopy.renderReminderIssue(
                  reminderSyncResult.issueCopy,
                  loc,
                );
          } else {
            reminderStatusBuilder = ([loc]) =>
                AiScheduleUiCopy.taskReminderSubmitted;
          }
        } else {
          final result = await todoProvider.addTodoWithResult(
            todo,
            waitForReminderSync: true,
            canWrite: originGuard,
          );
          if (!mounted || !_isCurrentAccountIntent()) return;
          final persisted =
              result != null && todoProvider.todos.any((t) => t.id == todo.id);
          if (!persisted) {
            _safeSetState(() {
              if (_disposed || !mounted) return;
              if (!_isCurrentAccountIntent()) return;
              _errorBuilder = () => AiScheduleUiCopy.genericSaveFailed;
            });
            return;
          }
        }
        if (!mounted || !_isCurrentAccountIntent()) return;
        outcome = _CreationOutcome(
          isCalendar: false,
          title: draft.title,
          startAt: draft.startAt,
          reminderFailed: reminderFailed,
          reminderStatusBuilder: reminderStatusBuilder,
          accountGeneration: _initialAccountGeneration,
          userId: _initialUserId,
        );
        _safeSetState(() {
          if (_disposed || !mounted) return;
          if (!_isCurrentAccountIntent()) return;
          _creationOutcome = outcome;
        });
      }
    } catch (e) {
      if (mounted &&
          outcome == null &&
          _isCurrentAccountIntent() &&
          (route == null || route.isCurrent)) {
        _safeSetState(() {
          if (_disposed || !mounted) return;
          if (!_isCurrentAccountIntent()) return;
          _errorBuilder = () => AiScheduleUiCopy.saveError(e);
        });
      }
    } finally {
      if (mounted) {
        _safeSetState(() {
          if (_disposed || !mounted) return;
          _saving = false;
        });
      }
    }

    if (outcome != null && mounted && _isCurrentAccountIntent()) {
      await _showCompletionDialog(outcome);
    }
  }

  Future<void> _showCompletionDialog(_CreationOutcome outcome) async {
    if (!mounted || !_isCurrentAccountIntent()) return;
    final route = _route ?? ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route != null && !route.isCurrent) {
      return;
    }

    final dialogRoute = DialogRoute<void>(
      context: context,
      builder: (dialogCtx) => _AiScheduleCompletionDialog(
        isCalendar: outcome.isCalendar,
        title: outcome.title,
        startAt: outcome.startAt,
        reminderFailed: outcome.reminderFailed,
        reminderStatusBuilder: outcome.reminderStatusBuilder,
        onDone: () {
          if (ModalRoute.of(dialogCtx)?.isCurrent == true) {
            Navigator.of(dialogCtx).pop();
          }
        },
      ),
    );
    _completionDialogRoute = dialogRoute;
    try {
      await navigator.push(dialogRoute);
    } finally {
      if (identical(_completionDialogRoute, dialogRoute)) {
        _completionDialogRoute = null;
      }
    }

    if (!mounted || !_isCurrentAccountIntent()) return;
    if (route != null && route.isCurrent) {
      navigator.pop(true);
    }
  }

  Future<void> _openNewGoal() async {
    if (_loading || _saving) return;
    final route = _route ?? ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (!_isCurrentAccountIntent()) {
      _handleAccountInvalidated();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const BrandRouteSurface(child: GoalEditScreen()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final hasBrandSurface =
        DesktopEmbeddedHostScope.isHosted(context) ||
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null ||
        context.findAncestorWidgetOfExactType<BrandBackground>() != null;
    final aiEnabled = context.watch<AiService>().enabled;
    final error = _errorBuilder?.call();
    return Scaffold(
      backgroundColor: hasBrandSurface ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(AiScheduleUiCopy.screenTitle),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (!aiEnabled) ...[
              AppInfoBanner(
                icon: Icons.offline_bolt_outlined,
                color: cs.tertiary,
                title: AiScheduleUiCopy.aiDisabledTitle,
                message: AiScheduleUiCopy.aiDisabledMessage,
              ),
              const SizedBox(height: 12),
            ],
            AppSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSectionHeader(
                    title: AiScheduleUiCopy.inputTitle,
                    subtitle: AiScheduleUiCopy.inputSubtitle,
                    padding: EdgeInsets.zero,
                    wrapText: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inputCtrl,
                    focusNode: _inputFocusNode,
                    autofocus: !_loading && _draft == null && _creationOutcome == null,
                    minLines: 3,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: AiScheduleUiCopy.inputHint,
                      prefixIcon: const Icon(Icons.auto_awesome_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: (_loading || _saving) ? null : _recognize,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (_loading)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                const Icon(Icons.manage_search_outlined),
                              Text(
                                _loading
                                    ? AiScheduleUiCopy.recognizing
                                    : AiScheduleUiCopy.recognize,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              AppInfoBanner(
                icon: Icons.error_outline,
                color: cs.error,
                title: AiScheduleUiCopy.errorTitle,
                message: error,
              ),
            ],
            if (_creationOutcome != null) ...[
              const SizedBox(height: 12),
              AppInfoBanner(
                icon: _creationOutcome!.reminderFailed
                    ? Icons.notification_important_outlined
                    : Icons.check_circle_outline,
                color: _creationOutcome!.reminderFailed
                    ? cs.tertiary
                    : cs.primary,
                title: AiScheduleUiCopy.dialogTitle(
                  isCalendar: _creationOutcome!.isCalendar,
                  reminderFailed: _creationOutcome!.reminderFailed,
                ),
                message: AiScheduleUiCopy.createdItemSummary(
                  _creationOutcome!.isCalendar,
                  _creationOutcome!.title,
                ),
              ),
              if (_draft != null) ...[
                const SizedBox(height: 12),
                _AiScheduleDraftCard(draft: _draft!),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _showCompletionDialog(_creationOutcome!),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        AiScheduleUiCopy.viewDetails,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final r = _route ?? ModalRoute.of(context);
                        if (r != null && r.isCurrent) {
                          Navigator.of(context).pop(true);
                        }
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        AiScheduleUiCopy.done,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (_draft != null) ...[
              const SizedBox(height: 12),
              if (_draft!.warning != null || _draft!.warningKind != null) ...[
                AppInfoBanner(
                  icon: Icons.warning_amber_outlined,
                  color: cs.tertiary,
                  title: AiScheduleUiCopy.warningTitle(_draft!),
                  message: AiScheduleUiCopy.warningMessage(_draft!),
                ),
                const SizedBox(height: 12),
              ],
              AppInfoBanner(
                icon: Icons.fact_check_outlined,
                color: cs.primary,
                title: AiScheduleUiCopy.draftTitle,
                message: _draft!.source == AiScheduleSource.ai
                    ? AiScheduleUiCopy.draftAiMessage
                    : AiScheduleUiCopy.draftFallbackMessage,
              ),
              const SizedBox(height: 12),
              _AiScheduleDraftCard(draft: _draft!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _create,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (_saving)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.check_circle_outline),
                    Text(
                      _saving
                          ? AiScheduleUiCopy.saving
                          : AiScheduleUiCopy.create,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('ai_schedule_new_goal_button'),
              onPressed: (_loading || _saving) ? null : _openNewGoal,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.flag_circle_outlined),
              label: Text(AiScheduleUiCopy.isEn() ? 'New goal' : '新建目标'),
            ),
          ],
        ),
      ),
    );
  }
}

CalendarEvent _toCalendarEvent(AiScheduleDraft draft) {
  final id = 'ai_${DateTime.now().microsecondsSinceEpoch}';
  return CalendarEvent(
    id: id,
    sourceId: id,
    title: draft.title,
    date: draft.startAt,
    endDate: draft.endAt,
    type: CalendarEventType.event,
    color: DesignTokens.defaultPrimary,
    subtitle: AiScheduleUiCopy.calendarSubtitle(draft.allDay),
    note: draft.notes,
  );
}

Color _aiScheduleCardBackground(BuildContext context) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final surfaceStyle = appSurfaceStyleOf(context);
  final cardFill = surfaceStyle?.cardFillColor;
  if (cardFill != null) {
    final backdrop = isDark
        ? theme.colorScheme.surface
        : theme.scaffoldBackgroundColor;
    return Color.alphaBlend(cardFill, backdrop);
  }
  return theme.colorScheme.surface;
}

Color _resolveAccessibleCardTextColor(
  BuildContext context,
  Color preferred, {
  double minContrast = 4.55,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final cardBg = _aiScheduleCardBackground(context);

  final effectivePreferred = Color.alphaBlend(preferred, cardBg);
  if (appContrastRatio(cardBg, effectivePreferred) >= minContrast) {
    return preferred;
  }

  final target = isDark ? Colors.white : const Color(0xFF111827);
  for (var t = 0.05; t <= 0.95; t += 0.05) {
    final candidate = Color.lerp(preferred, target, t)!;
    final effectiveCandidate = Color.alphaBlend(candidate, cardBg);
    if (appContrastRatio(cardBg, effectiveCandidate) >= minContrast) {
      return candidate;
    }
  }
  return appReadableForeground(cardBg, preferred);
}

class _AiScheduleDraftCard extends StatelessWidget {
  final AiScheduleDraft draft;

  const _AiScheduleDraftCard({required this.draft});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final endAt = draft.endAt;
    final labelColor = _resolveAccessibleCardTextColor(
      context,
      cs.onSurface.withValues(alpha: 0.62),
    );
    final warningColor = _resolveAccessibleCardTextColor(context, cs.tertiary);

    return AppSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: AiScheduleUiCopy.confirmCardTitle,
            subtitle: AiScheduleUiCopy.sourceLabel(draft.source),
            padding: EdgeInsets.zero,
            wrapText: true,
          ),
          const SizedBox(height: 12),
          _DraftRow(
            icon: draft.isCalendar
                ? Icons.event_available_outlined
                : Icons.check_circle_outline,
            label: AiScheduleUiCopy.typeLabel,
            value: draft.isCalendar
                ? AiScheduleUiCopy.calendarType
                : AiScheduleUiCopy.todoType,
            labelColor: labelColor,
          ),
          _DraftRow(
            icon: Icons.title_outlined,
            label: AiScheduleUiCopy.titleLabel,
            value: draft.title,
            labelColor: labelColor,
          ),
          _DraftRow(
            icon: Icons.schedule,
            label: AiScheduleUiCopy.startLabel,
            value: AppDateFormat.fullDateTime(context, draft.startAt),
            labelColor: labelColor,
          ),
          if (endAt != null && draft.isCalendar)
            _DraftRow(
              icon: Icons.timelapse_outlined,
              label: AiScheduleUiCopy.endLabel,
              value: AppDateFormat.fullDateTime(context, endAt),
              labelColor: labelColor,
            ),
          _DraftRow(
            icon: Icons.notifications_active_outlined,
            label: AiScheduleUiCopy.reminderLabel,
            value: draft.reminderEnabled
                ? AiScheduleUiCopy.reminderEnabled
                : AiScheduleUiCopy.reminderDisabled,
            labelColor: labelColor,
          ),
          if (draft.notes.isNotEmpty)
            _DraftRow(
              icon: Icons.notes_outlined,
              label: AiScheduleUiCopy.notesLabel,
              value: draft.notes,
              labelColor: labelColor,
            ),
          if (draft.subtasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              AiScheduleUiCopy.subtasksLabel,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: labelColor),
            ),
            const SizedBox(height: 4),
            for (final item in draft.subtasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(item, style: const TextStyle(height: 1.35)),
                    ),
                  ],
                ),
              ),
          ],
          if (draft.warning != null || draft.warningKind != null) ...[
            const SizedBox(height: 10),
            Text(
              AiScheduleUiCopy.warningMessage(draft),
              style: TextStyle(fontSize: 12, color: warningColor, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

class _DraftRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? labelColor;

  const _DraftRow({
    required this.icon,
    required this.label,
    required this.value,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveLabelColor =
        labelColor ??
        _resolveAccessibleCardTextColor(
          context,
          cs.onSurface.withValues(alpha: 0.62),
        );
    final textScaler = MediaQuery.textScalerOf(context);
    const labelFontSize = 13.0;
    final scaleRatio = textScaler.scale(labelFontSize) / labelFontSize;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isStacked = scaleRatio >= 1.35 || constraints.maxWidth < 300;
          final labelStyle = TextStyle(
            color: effectiveLabelColor,
            fontSize: labelFontSize,
          );
          const valueStyle = TextStyle(height: 1.35);

          if (isStacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label, style: labelStyle)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(value, style: valueStyle),
              ],
            );
          }

          final labelMaxWidth = (96.0 * scaleRatio).clamp(80.0, 160.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 48,
                  maxWidth: labelMaxWidth,
                ),
                child: Text(label, style: labelStyle),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(value, style: valueStyle)),
            ],
          );
        },
      ),
    );
  }
}

class _AiScheduleCompletionDialog extends StatefulWidget {
  final bool isCalendar;
  final String title;
  final DateTime startAt;
  final bool reminderFailed;
  final String Function([AppLocale? locale])? reminderStatusBuilder;
  final VoidCallback onDone;

  const _AiScheduleCompletionDialog({
    required this.isCalendar,
    required this.title,
    required this.startAt,
    required this.reminderFailed,
    this.reminderStatusBuilder,
    required this.onDone,
  });

  @override
  State<_AiScheduleCompletionDialog> createState() =>
      _AiScheduleCompletionDialogState();
}

class _AiScheduleCompletionDialogState
    extends State<_AiScheduleCompletionDialog> {
  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  String? _syncStatus() {
    try {
      return context.read<CloudSyncProvider>().localSaveSyncMessage(
        localSavedText: AiScheduleUiCopy.localSavedItem(widget.isCalendar),
      );
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reminderStatus = widget.reminderStatusBuilder?.call(I18n.current);
    final syncStatus = _syncStatus();
    return AppDialog(
      icon: Icon(
        widget.reminderFailed
            ? Icons.notification_important_outlined
            : widget.isCalendar
            ? Icons.event_available_outlined
            : Icons.check_circle_outline,
      ),
      title: Text(
        AiScheduleUiCopy.dialogTitle(
          isCalendar: widget.isCalendar,
          reminderFailed: widget.reminderFailed,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AiScheduleUiCopy.createdItemSummary(
              widget.isCalendar,
              widget.title,
            ),
            style: const TextStyle(height: 1.45),
          ),
          const SizedBox(height: 6),
          Text(
            AiScheduleUiCopy.startSummary(
              widget.isCalendar,
              AppDateFormat.fullDateTime(context, widget.startAt),
            ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (reminderStatus != null) ...[
            const SizedBox(height: 8),
            Text(
              reminderStatus,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: widget.reminderFailed ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          ],
          if (syncStatus != null) ...[
            const SizedBox(height: 8),
            Text(
              syncStatus,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: widget.onDone,
          child: Text(AiScheduleUiCopy.done),
        ),
      ],
    );
  }
}
