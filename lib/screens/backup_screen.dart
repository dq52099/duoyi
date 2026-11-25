import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../services/app_access_route_gate.dart';
import '../services/app_update_service.dart';
import '../services/date_item_action_origin.dart';
import 'package:flutter/material.dart';
import '../core/account_preference_writes.dart';
import '../core/data_settings_ui_copy.dart';
import '../core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:provider/provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../providers/anniversary_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/location_reminder_provider.dart';
import '../providers/note_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/quick_capture_template_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/user_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/achievement_provider.dart';
import '../providers/share_provider.dart';
import '../services/backup_service.dart';
import '../services/competitor_task_importer.dart';
import '../services/ics_exporter.dart';
import '../services/reminder_ringtone_settings.dart';
import '../services/web_file_download.dart';
import '../services/webdav_backup_service.dart';
import '../core/design_tokens.dart';
import '../widgets/surface_components.dart';
import '../widgets/controller_dialog.dart';
import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;

enum BackupEntryMode { backup, restore }

enum _ExportKind {
  fullJson,
  todosCsv,
  todosMd,
  habitsCsv,
  timeEntriesCsv,
  notesCsv,
  notesMd,
  diaryMd,
  diaryCsv,
  anniversariesCsv,
  anniversariesMd,
  goalsCsv,
  goalsMd,
}

enum _CompetitorImportSource { zhijianTime, ticktick, todoist, generic }

class _CompetitorImportDraft {
  final String raw;
  final _CompetitorImportSource source;
  final CompetitorFieldMapping fieldMapping;

  const _CompetitorImportDraft({
    required this.raw,
    required this.source,
    this.fieldMapping = const CompetitorFieldMapping(),
  });
}

class _CompetitorImportConfig {
  final _CompetitorImportSource source;
  final CompetitorFieldMapping fieldMapping;

  const _CompetitorImportConfig({
    required this.source,
    this.fieldMapping = const CompetitorFieldMapping(),
  });
}

class _CompetitorRollbackBanner {
  final int token;
  final int accountGeneration;
  final _CompetitorImportOrigin origin;
  bool isConsumed = false;

  _CompetitorRollbackBanner({
    required this.token,
    required this.accountGeneration,
    required this.origin,
  });

  void dispose() {
    if (!isConsumed) {
      origin.dispose();
    }
  }
}

class _CompetitorImportOrigin {
  final BuildContext screenContext;
  final ModalRoute<dynamic>? screenRoute;
  final int seq;
  final int accountGeneration;
  final bool Function() isActionCurrent;
  final TodoProvider todoProvider;
  final HabitProvider habitProvider;
  final NoteProvider noteProvider;
  final CalendarProvider calendarProvider;
  final AnniversaryProvider anniversaryProvider;
  final CountdownProvider countdownProvider;
  final TimeAuditProvider timeAuditProvider;
  final DateItemActionOrigin? anniversaryOrigin;
  final DateItemActionOrigin? countdownOrigin;
  final AuthProvider? auth;
  final AppLockProvider? lock;
  final AppUpdateService? update;

  late final int? sessionGeneration;
  late final bool wasLoggedIn;
  String? _userId;
  late final Object? _client;
  AuthSessionLease? _lease;
  bool _leaseFailed = false;
  late final int? lockAccessGeneration;
  late final bool wasLocked;
  late final bool wasMustUpdate;

  bool _expired = false;
  bool _disposed = false;
  bool _isTransferred = false;
  bool get isTransferred => _isTransferred;
  void markTransferred() => _isTransferred = true;
  final Object menuOwnerToken = Object();
  final Set<Route<dynamic>> _ownedRoutes = <Route<dynamic>>{};
  final List<AppAccessRouteGate> _gates = <AppAccessRouteGate>[];

  _CompetitorImportOrigin({
    required this.screenContext,
    required this.screenRoute,
    required this.seq,
    required this.accountGeneration,
    required this.isActionCurrent,
    required this.todoProvider,
    required this.habitProvider,
    required this.noteProvider,
    required this.calendarProvider,
    required this.anniversaryProvider,
    required this.countdownProvider,
    required this.timeAuditProvider,
    required this.anniversaryOrigin,
    required this.countdownOrigin,
    required this.auth,
    required this.lock,
    required this.update,
  }) {
    sessionGeneration = auth?.sessionGeneration;
    wasLoggedIn = auth?.state.isLoggedIn ?? false;
    final uid = auth?.state.userId?.trim();
    _userId = (uid == null || uid.isEmpty) ? null : uid;
    _client = _clientSnapshot();
    if (wasLoggedIn && auth != null) {
      try {
        _lease = auth!.captureSessionLease();
      } catch (_) {
        _leaseFailed = true;
      }
    }
    wasLocked = lock?.isLocked ?? false;
    lockAccessGeneration = lock?.accessGeneration;
    wasMustUpdate = update?.mustUpdate ?? false;

    if (wasLocked || wasMustUpdate || _leaseFailed) {
      _expired = true;
    }

    auth?.addListener(_observeAuthority);
    lock?.addListener(_observeAuthority);
    update?.addListener(_observeAuthority);
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _observeAuthority,
    );
    screenRoute?.secondaryAnimation?.addListener(_observeSourceCover);

    try {
      for (final observer in Navigator.of(screenContext).widget.observers) {
        if (observer is AppAccessRouteGate) {
          _gates.add(observer);
          observer.routeRevision.addListener(_observeRoute);
        }
      }
    } catch (_) {}
  }

  Object? _clientSnapshot() => (
    auth?.client,
    auth?.client.token,
    auth?.client.baseUrl,
    auth?.state.token,
  );

  void registerOwnedRoute(Route<dynamic> route) {
    if (_expired || _disposed) return;
    if (_ownedRoutes.add(route)) {
      if (route is TransitionRoute<dynamic>) {
        route.completed.then((_) {
          _ownedRoutes.remove(route);
        });
      } else {
        route.popped.then((_) {
          _ownedRoutes.remove(route);
        });
      }
    }
  }

  void _observeAuthority() {
    if (_disposed || _expired) return;
    if (!isCurrent(checkRoute: false)) {
      _invalidate();
    }
  }

  void _observeSourceCover() {
    if (_disposed || _expired) return;
    if (_ownedRoutes.isEmpty &&
        (screenRoute?.secondaryAnimation?.value ?? 0) > 0) {
      _invalidate();
    }
  }

  void _observeRoute() {
    if (_disposed || _expired) return;
    for (final gate in _gates) {
      final current = gate.currentRoute;
      if (current == null) continue;
      if (identical(current, screenRoute)) continue;
      if (_ownedRoutes.contains(current)) continue;
      if (current.settings.name == 'AppAnchoredDropdownMenu') {
        final metadata = current.settings.arguments;
        if (metadata is AppAnchoredDropdownMenuMetadata &&
            identical(metadata.ownerToken, menuOwnerToken)) {
          metadata.onRouteCreated?.call(current);
          registerOwnedRoute(current);
          continue;
        }
        _invalidate();
        return;
      }
      _invalidate();
      return;
    }
  }

  void _invalidate() {
    if (_expired || _disposed) return;
    _expired = true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    auth?.removeListener(_observeAuthority);
    lock?.removeListener(_observeAuthority);
    update?.removeListener(_observeAuthority);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _observeAuthority,
    );
    screenRoute?.secondaryAnimation?.removeListener(_observeSourceCover);
    for (final gate in _gates) {
      gate.routeRevision.removeListener(_observeRoute);
    }
    _gates.clear();
    _ownedRoutes.clear();
  }

  bool isCurrent({
    ModalRoute<dynamic>? currentModalRoute,
    bool checkDates = true,
    bool checkRoute = true,
    bool checkParentActiveOnly = false,
  }) {
    if (_expired || _disposed || _leaseFailed) return false;
    if (wasLocked || wasMustUpdate) return false;
    if (!screenContext.mounted) return false;
    if (!isActionCurrent()) return false;
    if (screenRoute != null && !screenRoute!.isActive) return false;

    if (checkRoute) {
      if (currentModalRoute != null) {
        if (!currentModalRoute.isActive) {
          return false;
        }
        if (!checkParentActiveOnly && !currentModalRoute.isCurrent) {
          return false;
        }
        if (!_ownedRoutes.contains(currentModalRoute)) {
          return false;
        }
      } else {
        if (screenRoute != null && !screenRoute!.isCurrent) {
          return false;
        }
      }
    }

    try {
      if (!identical(screenContext.read<TodoProvider>(), todoProvider) ||
          !identical(screenContext.read<HabitProvider>(), habitProvider) ||
          !identical(screenContext.read<NoteProvider>(), noteProvider) ||
          !identical(
            screenContext.read<CalendarProvider>(),
            calendarProvider,
          ) ||
          !identical(
            screenContext.read<AnniversaryProvider>(),
            anniversaryProvider,
          ) ||
          !identical(
            screenContext.read<CountdownProvider>(),
            countdownProvider,
          ) ||
          !identical(
            screenContext.read<TimeAuditProvider>(),
            timeAuditProvider,
          )) {
        return false;
      }
      if (!identical(screenContext.read<AuthProvider?>(), auth) ||
          !identical(screenContext.read<AppLockProvider?>(), lock) ||
          !identical(screenContext.read<AppUpdateService?>(), update)) {
        return false;
      }
      if (lock != null &&
          (lock!.isLocked || lock!.accessGeneration != lockAccessGeneration)) {
        _expired = true;
        return false;
      }
      if (update != null && update!.mustUpdate) {
        _expired = true;
        return false;
      }
      final currentAuth = auth;
      if (currentAuth != null) {
        if (currentAuth.sessionGeneration != sessionGeneration ||
            currentAuth.state.isLoggedIn != wasLoggedIn ||
            currentAuth.isAccountTransitionInProgress ||
            currentAuth.isLocalAccountDataBlocked ||
            (_lease != null && !currentAuth.isSessionLeaseCurrent(_lease!)) ||
            _clientSnapshot() != _client) {
          _expired = true;
          return false;
        }
        final currentUid = currentAuth.state.userId?.trim();
        if ((_userId?.isNotEmpty ?? false) && _userId != currentUid) {
          _expired = true;
          return false;
        }
        if (currentUid?.isNotEmpty ?? false) {
          _userId ??= currentUid;
        }
      }
      if (checkDates) {
        if (anniversaryOrigin != null &&
            !anniversaryOrigin!.isCurrent(checkRoute: false)) {
          return false;
        }
        if (countdownOrigin != null &&
            !countdownOrigin!.isCurrent(checkRoute: false)) {
          return false;
        }
      }
    } catch (_) {
      return false;
    }
    return true;
  }
}

const _competitorFieldMappingTargets = <(String, String)>[
  ('title', '标题/名称'),
  ('date', '日期/开始日期'),
  ('due', '截止时间/结束时间'),
  ('list', '清单/项目'),
  ('tags', '标签'),
  ('priority', '优先级'),
  ('quadrant', '四象限'),
  ('completed', '完成状态'),
  ('completedAt', '完成时间'),
  ('reminder', '提醒时间'),
  ('repeat', '重复规则'),
  ('notes', '备注/描述'),
  ('type', '模块类型'),
  ('target', '习惯目标次数'),
  ('unit', '习惯单位'),
  ('category', '分类/分组'),
  ('duration', '时间足迹时长'),
];

class _CompetitorImportApplySummary {
  final int todoInserted;
  final int habitInserted;
  final int noteInserted;
  final int eventInserted;
  final int anniversaryInserted;
  final int countdownInserted;
  final int timeEntryInserted;
  final int skippedRows;
  final int skippedDuplicates;
  final List<String> reminderSyncIssues;

  const _CompetitorImportApplySummary({
    required this.todoInserted,
    required this.habitInserted,
    required this.noteInserted,
    required this.eventInserted,
    required this.anniversaryInserted,
    required this.countdownInserted,
    required this.timeEntryInserted,
    required this.skippedRows,
    required this.skippedDuplicates,
    this.reminderSyncIssues = const <String>[],
  });

  int get inserted =>
      todoInserted +
      habitInserted +
      noteInserted +
      eventInserted +
      anniversaryInserted +
      countdownInserted +
      timeEntryInserted;

  int get skipped => skippedRows + skippedDuplicates;

  bool get hasReminderSyncIssues => reminderSyncIssues.isNotEmpty;
}

class BackupScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final BackupEntryMode initialMode;

  const BackupScreen({super.key, this.initialMode = BackupEntryMode.backup});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String? _exported;
  String? _exportedTitle;
  _ExportKind? _currentExportKind;
  bool _busy = false;
  WebDavBackupConfig _webDavConfig = WebDavBackupConfig.empty();
  int _actionSeq = 0;
  int _configReadSeq = 0;
  int _rollbackTokenSeq = 0;
  int? _currentRollbackToken;
  int? _competitorRollbackGeneration;
  _CompetitorRollbackBanner? _activeBanner;
  final Set<_CompetitorImportOrigin> _activeRollbackOperations =
      <_CompetitorImportOrigin>{};

  void _dismissActiveBanner() {
    final banner = _activeBanner;
    if (banner != null) {
      _activeBanner = null;
      banner.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountDataChanged,
    );
    _loadWebDavConfig();
  }

  @override
  void dispose() {
    _dismissActiveBanner();
    for (final op in List<_CompetitorImportOrigin>.of(
      _activeRollbackOperations,
    )) {
      op.dispose();
    }
    _activeRollbackOperations.clear();
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountDataChanged,
    );
    super.dispose();
  }

  void _onAccountDataChanged() {
    if (!mounted) return;
    _dismissActiveBanner();
    for (final op in List<_CompetitorImportOrigin>.of(
      _activeRollbackOperations,
    )) {
      op.dispose();
    }
    _activeRollbackOperations.clear();
    _actionSeq++;
    _configReadSeq++;
    _currentRollbackToken = null;
    _competitorRollbackGeneration = null;
    _busy = false;
    _exported = null;
    _exportedTitle = null;
    _currentExportKind = null;
    _webDavConfig = WebDavBackupConfig.empty();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {});
    _loadWebDavConfig();
  }

  bool _isCurrentAction(int seq, int accountGeneration) =>
      mounted &&
      seq == _actionSeq &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(accountGeneration);

  _CompetitorImportOrigin? _captureCompetitorImportOrigin(
    int seq, {
    bool tasksOnly = false,
  }) {
    if (!mounted) return null;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive || !route.isCurrent) return null;
    final currentGeneration = AccountLocalDataCleaner.accountDataGeneration;
    try {
      final todoProvider = context.read<TodoProvider>();
      final habitProvider = context.read<HabitProvider>();
      final noteProvider = context.read<NoteProvider>();
      final calendarProvider = context.read<CalendarProvider>();
      final anniversaryProvider = context.read<AnniversaryProvider>();
      final countdownProvider = context.read<CountdownProvider>();
      final timeAuditProvider = context.read<TimeAuditProvider>();
      final auth = context.read<AuthProvider?>();
      final lock = context.read<AppLockProvider?>();
      final update = context.read<AppUpdateService?>();
      final anniversaryOrigin = tasksOnly
          ? null
          : DateItemActionOrigin.anniversary(context);
      final countdownOrigin = tasksOnly
          ? null
          : DateItemActionOrigin.countdown(context);
      final origin = _CompetitorImportOrigin(
        screenContext: context,
        screenRoute: route,
        seq: seq,
        accountGeneration: currentGeneration,
        isActionCurrent: () => _isCurrentAction(seq, currentGeneration),
        todoProvider: todoProvider,
        habitProvider: habitProvider,
        noteProvider: noteProvider,
        calendarProvider: calendarProvider,
        anniversaryProvider: anniversaryProvider,
        countdownProvider: countdownProvider,
        timeAuditProvider: timeAuditProvider,
        anniversaryOrigin: anniversaryOrigin,
        countdownOrigin: countdownOrigin,
        auth: auth,
        lock: lock,
        update: update,
      );
      if (!origin.isCurrent()) {
        origin.dispose();
        return null;
      }
      return origin;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadWebDavConfig() async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final readSeq = ++_configReadSeq;
    try {
      final config = await WebDavBackupService.loadConfig();
      if (!mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          ) ||
          readSeq != _configReadSeq) {
        return;
      }
      setState(() => _webDavConfig = config);
    } catch (e) {
      if (e is AccountPreferenceWriteCanceled ||
          !mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          ) ||
          readSeq != _configReadSeq) {
        return;
      }
    }
  }

  String _formatWipeError(Object? error) {
    return DataSettingsUiCopy.isEn
        ? 'Failed to clear local data. Please try again.'
        : '清空本地数据失败，请重试';
  }

  String _formatCopyError(Object? error) {
    return DataSettingsUiCopy.isEn
        ? 'Failed to copy to clipboard. Please try again.'
        : '复制到剪贴板失败，请重试';
  }

  Future<void> _exportAll() async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final seq = ++_actionSeq;
    setState(() => _busy = true);
    try {
      final text = await BackupService.exportAll();
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      setState(() {
        _exported = text;
        _currentExportKind = _ExportKind.fullJson;
        _exportedTitle = DataSettingsUiCopy.fullBackupJsonTitle;
      });
    } catch (e) {
      if (!mounted ||
          e is AccountPreferenceWriteCanceled ||
          !_isCurrentAction(seq, accountGeneration)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatExportError(e))),
      );
    } finally {
      if (mounted && _isCurrentAction(seq, accountGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  void _showExport(_ExportKind kind, String text) {
    setState(() {
      _currentExportKind = kind;
      _exportedTitle = null;
      _exported = text;
    });
  }

  String _activeExportedTitle() {
    return switch (_currentExportKind) {
      _ExportKind.fullJson => DataSettingsUiCopy.fullBackupJsonTitle,
      _ExportKind.todosCsv => DataSettingsUiCopy.exportTitleTodoCsv,
      _ExportKind.todosMd => DataSettingsUiCopy.exportTitleTodoMd,
      _ExportKind.habitsCsv => DataSettingsUiCopy.exportTitleHabitCsv,
      _ExportKind.timeEntriesCsv => DataSettingsUiCopy.exportTitleTimeEntryCsv,
      _ExportKind.notesCsv => DataSettingsUiCopy.exportTitleNoteCsv,
      _ExportKind.notesMd => DataSettingsUiCopy.exportTitleNoteMd,
      _ExportKind.diaryMd => DataSettingsUiCopy.exportTitleDiaryMd,
      _ExportKind.diaryCsv => DataSettingsUiCopy.exportTitleDiaryCsv,
      _ExportKind.anniversariesCsv =>
        DataSettingsUiCopy.exportTitleAnniversaryCsv,
      _ExportKind.anniversariesMd =>
        DataSettingsUiCopy.exportTitleAnniversaryMd,
      _ExportKind.goalsCsv => DataSettingsUiCopy.exportTitleGoalCsv,
      _ExportKind.goalsMd => DataSettingsUiCopy.exportTitleGoalMd,
      null => _exportedTitle ?? DataSettingsUiCopy.exportContent,
    };
  }

  String _exportFileName(_ExportKind? kind) {
    final now = DateTime.now();
    final dateTag =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return switch (kind) {
      _ExportKind.fullJson => 'duoyi_backup_$dateTag.json',
      _ExportKind.todosCsv => 'duoyi_todos_$dateTag.csv',
      _ExportKind.todosMd => 'duoyi_todos_$dateTag.md',
      _ExportKind.habitsCsv => 'duoyi_habits_$dateTag.csv',
      _ExportKind.timeEntriesCsv => 'duoyi_time_entries_$dateTag.csv',
      _ExportKind.notesCsv => 'duoyi_notes_$dateTag.csv',
      _ExportKind.notesMd => 'duoyi_notes_$dateTag.md',
      _ExportKind.diaryMd => 'duoyi_diary_$dateTag.md',
      _ExportKind.diaryCsv => 'duoyi_diary_$dateTag.csv',
      _ExportKind.anniversariesCsv => 'duoyi_anniversaries_$dateTag.csv',
      _ExportKind.anniversariesMd => 'duoyi_anniversaries_$dateTag.md',
      _ExportKind.goalsCsv => 'duoyi_goals_$dateTag.csv',
      _ExportKind.goalsMd => 'duoyi_goals_$dateTag.md',
      null => 'duoyi_export_$dateTag.txt',
    };
  }

  Future<void> _downloadExportedText(_ExportKind? kind, String text) async {
    if (_busy) return;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final seq = ++_actionSeq;
    setState(() => _busy = true);
    final fileName = _exportFileName(kind);
    try {
      final result = await WebFileDownload.saveText(
        content: text,
        fileName: fileName,
        shareSubject: _activeExportedTitle(),
        canProceed: () =>
            mounted &&
            _isCurrentAction(seq, accountGeneration) &&
            _exported == text,
      );
      if (!mounted ||
          !_isCurrentAction(seq, accountGeneration) ||
          !result.saved) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) => Text(
              locale == AppLocale.en
                  ? 'Exported file: $fileName'
                  : '已导出文件：$fileName',
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted ||
          e is AccountPreferenceWriteCanceled ||
          !_isCurrentAction(seq, accountGeneration)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatExportError(e))),
      );
    } finally {
      if (mounted && _isCurrentAction(seq, accountGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _downloadExported() async {
    final text = _exported;
    if (text == null) return;
    await _downloadExportedText(_currentExportKind, text);
  }

  Future<void> _exportAndDownloadAllJson() async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final seq = ++_actionSeq;
    setState(() => _busy = true);
    try {
      final text = await BackupService.exportAll();
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      setState(() {
        _exported = text;
        _currentExportKind = _ExportKind.fullJson;
        _exportedTitle = DataSettingsUiCopy.fullBackupJsonTitle;
      });
      final fileName = _exportFileName(_ExportKind.fullJson);
      final result = await WebFileDownload.saveText(
        content: text,
        fileName: fileName,
        mimeType: 'application/json;charset=utf-8',
        shareSubject: DataSettingsUiCopy.fullBackupJsonTitle,
        canProceed: () =>
            mounted && _isCurrentAction(seq, accountGeneration),
      );
      if (!mounted ||
          !_isCurrentAction(seq, accountGeneration) ||
          !result.saved) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) => Text(
              locale == AppLocale.en
                  ? 'Exported JSON backup: $fileName'
                  : '已导出 JSON 备份：$fileName',
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted ||
          e is AccountPreferenceWriteCanceled ||
          !_isCurrentAction(seq, accountGeneration)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatExportError(e))),
      );
    } finally {
      if (mounted && _isCurrentAction(seq, accountGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _copy() async {
    if (_busy) return;
    final text = _exported;
    if (text == null) return;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final actionSeq = _actionSeq;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          ) ||
          actionSeq != _actionSeq ||
          _exported != text) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) =>
                Text(DataSettingsUiCopy.copiedToClipboard),
          ),
        ),
      );
    } catch (e) {
      if (e is AccountPreferenceWriteCanceled ||
          !mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          ) ||
          actionSeq != _actionSeq ||
          _exported != text) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) => Text(_formatCopyError(e)),
          ),
        ),
      );
    }
  }

  Future<void> _import({bool merge = false}) async {
    final todoProvider = context.read<TodoProvider>();
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final seq = ++_actionSeq;
    final ctrl = TextEditingController();
    final raw = await showControllerDialog<String>(
      context: context,
      controllers: [ctrl],
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => AppDialog(
          title: Text(DataSettingsUiCopy.importDialogTitle(merge)),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                maxLines: 10,
                decoration: InputDecoration(
                  hintText: DataSettingsUiCopy.importDialogPasteHint,
                ),
              ),
              // 覆盖=真删数据：备份中不存在的本机数据会被删除，必须写明后果，
              // 避免用户用旧备份覆盖后误以为"还原失败"。
              if (!merge) ...[
                const SizedBox(height: 8),
                Text(
                  I18n.tr('backup.overwrite.will_delete_missing'),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(DataSettingsUiCopy.confirmImport),
            ),
          ],
        ),
      ),
    );
    if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
    if (raw == null || raw.trim().isEmpty) return;

    _currentRollbackToken = null;
    _competitorRollbackGeneration = null;
    setState(() => _busy = true);
    try {
      final count = await todoProvider.runExternalStorageUpdate(
        () async => await BackupService.importAll(
          raw,
          merge: merge,
          // 覆盖=还原到备份快照：备份中不存在的本机数据一并删除，弹窗已警告。
          // 服务层 `clearMissing && !merge` 守卫保证 merge 合并入口不受影响。
          clearMissing: true,
        ),
        expectedAccountDataGeneration: accountGeneration,
      );
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      _currentRollbackToken = null;
      _competitorRollbackGeneration = null;
      await _reloadAll(accountGeneration: accountGeneration, seq: seq);
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.importSuccess(merge, count))),
      );
    } catch (e) {
      if (!mounted ||
          e is AccountPreferenceWriteCanceled ||
          !_isCurrentAction(seq, accountGeneration)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatImportError(e))),
      );
    } finally {
      if (mounted && _isCurrentAction(seq, accountGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String?> _pickImportTextFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Backup or CSV',
          extensions: ['json', 'csv', 'txt'],
          mimeTypes: ['application/json', 'text/csv', 'text/plain'],
        ),
      ],
    );
    return file?.readAsString();
  }

  Future<void> _importBackupFile({required bool merge}) async {
    _dismissActiveBanner();
    final todoProvider = context.read<TodoProvider>();
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final seq = ++_actionSeq;
    // 覆盖=真删数据：文件覆盖与粘贴覆盖导入 / WebDAV 覆盖恢复一致，
    // 必须先弹窗写明删除后果，防止误触一次即静默删除本机数据。
    if (!merge) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => AppDialog(
            title: Text(DataSettingsUiCopy.importFileOverwriteDialogTitle),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(DataSettingsUiCopy.importFileOverwriteExplanation),
                // 覆盖=真删数据：写明缺失数据将被删除的后果。
                const SizedBox(height: 8),
                Text(
                  I18n.tr('backup.overwrite.will_delete_missing'),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(DataSettingsUiCopy.selectFile),
              ),
            ],
          ),
        ),
      );
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      if (ok != true) return;
    }
    _currentRollbackToken = null;
    _competitorRollbackGeneration = null;
    setState(() => _busy = true);
    try {
      final raw = await _pickImportTextFile();
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      if (raw == null || raw.trim().isEmpty) {
        return;
      }
      final count = await todoProvider.runExternalStorageUpdate(
        () async => await BackupService.importAll(
          raw,
          merge: merge,
          // 覆盖=还原到备份快照：备份中不存在的本机数据一并删除，弹窗已警告。
          // 服务层 `clearMissing && !merge` 守卫保证 merge 合并入口不受影响。
          clearMissing: true,
        ),
        expectedAccountDataGeneration: accountGeneration,
      );
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      _currentRollbackToken = null;
      _competitorRollbackGeneration = null;
      await _reloadAll(accountGeneration: accountGeneration, seq: seq);
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(DataSettingsUiCopy.importFileSuccess(merge, count)),
        ),
      );
    } catch (e) {
      if (!mounted ||
          e is AccountPreferenceWriteCanceled ||
          !_isCurrentAction(seq, accountGeneration)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatFileImportError(e))),
      );
    } finally {
      if (mounted && _isCurrentAction(seq, accountGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _importTasksFromOtherApps() async {
    _dismissActiveBanner();
    final seq = ++_actionSeq;
    final origin = _captureCompetitorImportOrigin(seq, tasksOnly: true);
    if (origin == null || !origin.isCurrent()) {
      origin?.dispose();
      return;
    }
    try {
      final draft = await _askCompetitorImportText(
        tasksOnly: true,
        origin: origin,
      );
      if (!mounted || !origin.isCurrent()) return;
      if (draft == null) return;
      await _previewAndImportCompetitorData(
        draft,
        tasksOnly: true,
        origin: origin,
      );
    } finally {
      if (!origin.isTransferred) {
        origin.dispose();
      }
    }
  }

  Future<void> _importProductivityDataFromOtherApps() async {
    _dismissActiveBanner();
    final seq = ++_actionSeq;
    final origin = _captureCompetitorImportOrigin(seq, tasksOnly: false);
    if (origin == null || !origin.isCurrent()) {
      origin?.dispose();
      return;
    }
    try {
      final draft = await _askCompetitorImportText(
        tasksOnly: false,
        origin: origin,
      );
      if (!mounted || !origin.isCurrent()) return;
      if (draft == null) return;
      await _previewAndImportCompetitorData(
        draft,
        tasksOnly: false,
        origin: origin,
      );
    } finally {
      if (!origin.isTransferred) {
        origin.dispose();
      }
    }
  }

  Future<void> _importProductivityDataFile() async {
    _dismissActiveBanner();
    final seq = ++_actionSeq;
    final origin = _captureCompetitorImportOrigin(seq, tasksOnly: false);
    if (origin == null || !origin.isCurrent()) {
      origin?.dispose();
      return;
    }
    try {
      final raw = await _pickImportTextFile();
      if (!mounted || !origin.isCurrent()) return;
      if (raw == null || raw.trim().isEmpty) return;
      final config = await _selectCompetitorImportSource(origin: origin);
      if (!mounted || !origin.isCurrent()) return;
      if (config == null) return;
      await _previewAndImportCompetitorData(
        _CompetitorImportDraft(
          raw: raw,
          source: config.source,
          fieldMapping: config.fieldMapping,
        ),
        tasksOnly: false,
        origin: origin,
      );
    } catch (e) {
      if (!mounted ||
          e is AccountPreferenceWriteCanceled ||
          !origin.isCurrent()) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(DataSettingsUiCopy.formatFileMigrationError(e)),
          ),
        );
    } finally {
      if (!origin.isTransferred) {
        origin.dispose();
      }
    }
  }

  Future<_CompetitorImportDraft?> _askCompetitorImportText({
    required bool tasksOnly,
    _CompetitorImportOrigin? origin,
  }) async {
    final ctrl = TextEditingController();
    var source = _CompetitorImportSource.zhijianTime;
    var fieldMapping = const CompetitorFieldMapping();
    final draft = await showControllerDialog<_CompetitorImportDraft>(
      context: context,
      controllers: [ctrl],
      onRouteCreated: origin?.registerOwnedRoute,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => AppDialog(
            title: Text(
              DataSettingsUiCopy.competitorImportDialogTitle(tasksOnly),
            ),
            maxWidth: 560,
            content: AppSecondaryControlTheme(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppDropdownField<_CompetitorImportSource>(
                      initialValue: source,
                      wrapSelectedText: true,
                      onMenuRouteCreated: origin?.registerOwnedRoute,
                      menuOwnerToken: origin?.menuOwnerToken,
                      isSelectionAllowed: () {
                        if (!ctx.mounted) return false;
                        final dialogRoute = ModalRoute.of(ctx);
                        if (dialogRoute == null || !dialogRoute.isActive) {
                          return false;
                        }
                        return origin == null ||
                            origin.isCurrent(
                              currentModalRoute: dialogRoute,
                              checkParentActiveOnly: true,
                            );
                      },
                      isInteractionAllowed: () {
                        if (!ctx.mounted) return false;
                        final dialogRoute = ModalRoute.of(ctx);
                        if (dialogRoute == null || !dialogRoute.isCurrent) {
                          return false;
                        }
                        return origin == null ||
                            origin.isCurrent(currentModalRoute: dialogRoute);
                      },
                      decoration: InputDecoration(
                        labelText: DataSettingsUiCopy.sourceLabel,
                        prefixIcon: const Icon(Icons.source_outlined),
                      ),
                      items: _CompetitorImportSource.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(_competitorSourceLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        if (!ctx.mounted) return;
                        final dialogRoute = ModalRoute.of(ctx);
                        if (dialogRoute == null || !dialogRoute.isCurrent) {
                          return;
                        }
                        if (origin != null &&
                            !origin.isCurrent(currentModalRoute: dialogRoute)) {
                          return;
                        }
                        setDialogState(() => source = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _competitorSourceHint(source),
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          ctx,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        if (!ctx.mounted) return;
                        final dialogRoute = ModalRoute.of(ctx);
                        if (dialogRoute == null || !dialogRoute.isCurrent) {
                          return;
                        }
                        if (origin != null &&
                            !origin.isCurrent(currentModalRoute: dialogRoute)) {
                          return;
                        }
                        final updated = await _editCompetitorFieldMapping(
                          fieldMapping,
                          origin: origin,
                          parentRoute: dialogRoute,
                        );
                        if (updated == null) return;
                        if (!ctx.mounted) return;
                        final recheckRoute = ModalRoute.of(ctx);
                        if (recheckRoute == null ||
                            !recheckRoute.isActive ||
                            !recheckRoute.isCurrent) {
                          return;
                        }
                        if (origin != null &&
                            !origin.isCurrent(
                              currentModalRoute: recheckRoute,
                            )) {
                          return;
                        }
                        setDialogState(() => fieldMapping = updated);
                      },
                      icon: const Icon(Icons.schema_outlined),
                      label: Text(DataSettingsUiCopy.advancedFieldMapping),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _fieldMappingSummary(fieldMapping),
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          ctx,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ctrl,
                      maxLines: 12,
                      decoration: InputDecoration(
                        hintText: DataSettingsUiCopy.competitorImportPasteHint(
                          tasksOnly,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (!ctx.mounted) return;
                  final dialogRoute = ModalRoute.of(ctx);
                  if (dialogRoute == null || !dialogRoute.isCurrent) {
                    return;
                  }
                  Navigator.pop(ctx);
                },
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: () {
                  if (!ctx.mounted) return;
                  final dialogRoute = ModalRoute.of(ctx);
                  if (dialogRoute == null || !dialogRoute.isCurrent) {
                    return;
                  }
                  if (origin != null &&
                      !origin.isCurrent(currentModalRoute: dialogRoute)) {
                    return;
                  }
                  final raw = ctrl.text.trim();
                  if (raw.isEmpty) return;
                  Navigator.pop(
                    ctx,
                    _CompetitorImportDraft(
                      raw: raw,
                      source: source,
                      fieldMapping: fieldMapping,
                    ),
                  );
                },
                child: Text(
                  DataSettingsUiCopy.competitorImportPreviewAction(tasksOnly),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return draft;
  }

  Future<_CompetitorImportConfig?> _selectCompetitorImportSource({
    required _CompetitorImportOrigin origin,
  }) async {
    var source = _CompetitorImportSource.zhijianTime;
    var fieldMapping = const CompetitorFieldMapping();
    final chooserRoute = createControllerDialogRoute<_CompetitorImportConfig>(
      context: context,
      onRouteCreated: origin.registerOwnedRoute,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => AppDialog(
            title: Text(DataSettingsUiCopy.importCompetitorFileSourceTitle),
            content: AppSecondaryControlTheme(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppDropdownField<_CompetitorImportSource>(
                    initialValue: source,
                    wrapSelectedText: true,
                    onMenuRouteCreated: origin.registerOwnedRoute,
                    menuOwnerToken: origin.menuOwnerToken,
                    isSelectionAllowed: () {
                      if (!ctx.mounted) return false;
                      final dialogRoute = ModalRoute.of(ctx);
                      if (dialogRoute == null || !dialogRoute.isActive) {
                        return false;
                      }
                      return origin.isCurrent(
                        currentModalRoute: dialogRoute,
                        checkParentActiveOnly: true,
                      );
                    },
                    isInteractionAllowed: () {
                      if (!ctx.mounted) return false;
                      final dialogRoute = ModalRoute.of(ctx);
                      if (dialogRoute == null || !dialogRoute.isCurrent) {
                        return false;
                      }
                      return origin.isCurrent(currentModalRoute: dialogRoute);
                    },
                    decoration: InputDecoration(
                      labelText: DataSettingsUiCopy.sourceLabel,
                      prefixIcon: const Icon(Icons.source_outlined),
                    ),
                    items: _CompetitorImportSource.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_competitorSourceLabel(value)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      if (!ctx.mounted) return;
                      final dialogRoute = ModalRoute.of(ctx);
                      if (dialogRoute == null || !dialogRoute.isCurrent) {
                        return;
                      }
                      if (!origin.isCurrent(currentModalRoute: dialogRoute)) {
                        return;
                      }
                      setDialogState(() => source = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _competitorSourceHint(source),
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      if (!ctx.mounted) return;
                      final dialogRoute = ModalRoute.of(ctx);
                      if (dialogRoute == null || !dialogRoute.isCurrent) {
                        return;
                      }
                      if (!origin.isCurrent(currentModalRoute: dialogRoute)) {
                        return;
                      }
                      final updated = await _editCompetitorFieldMapping(
                        fieldMapping,
                        origin: origin,
                        parentRoute: dialogRoute,
                      );
                      if (updated == null) return;
                      if (!ctx.mounted) return;
                      final recheckRoute = ModalRoute.of(ctx);
                      if (recheckRoute == null ||
                          !recheckRoute.isActive ||
                          !recheckRoute.isCurrent) {
                        return;
                      }
                      if (!origin.isCurrent(currentModalRoute: recheckRoute)) {
                        return;
                      }
                      setDialogState(() => fieldMapping = updated);
                    },
                    icon: const Icon(Icons.schema_outlined),
                    label: Text(DataSettingsUiCopy.advancedFieldMapping),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _fieldMappingSummary(fieldMapping),
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (!ctx.mounted) return;
                  final dialogRoute = ModalRoute.of(ctx);
                  if (dialogRoute == null || !dialogRoute.isCurrent) {
                    return;
                  }
                  Navigator.pop(ctx);
                },
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: () {
                  if (!ctx.mounted) return;
                  final dialogRoute = ModalRoute.of(ctx);
                  if (dialogRoute == null || !dialogRoute.isCurrent) {
                    return;
                  }
                  if (!origin.isCurrent(currentModalRoute: dialogRoute)) {
                    return;
                  }
                  Navigator.pop(
                    ctx,
                    _CompetitorImportConfig(
                      source: source,
                      fieldMapping: fieldMapping,
                    ),
                  );
                },
                child: Text(
                  DataSettingsUiCopy.importCompetitorFileSourceAction,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final result = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<_CompetitorImportConfig>(chooserRoute);
    await chooserRoute.completed;
    return result;
  }

  Future<void> _previewAndImportCompetitorData(
    _CompetitorImportDraft draft, {
    required bool tasksOnly,
    _CompetitorImportOrigin? origin,
    int? seq,
  }) async {
    final effectiveOrigin =
        origin ??
        _captureCompetitorImportOrigin(
          seq ?? ++_actionSeq,
          tasksOnly: tasksOnly,
        );
    if (effectiveOrigin == null || !effectiveOrigin.isCurrent()) {
      if (origin == null) {
        effectiveOrigin?.dispose();
      }
      return;
    }
    final currentGeneration = effectiveOrigin.accountGeneration;
    final currentSeq = effectiveOrigin.seq;
    final parsed = const CompetitorTaskImporter().parse(
      draft.raw,
      fieldMapping: draft.fieldMapping,
    );
    final recognized = tasksOnly ? parsed.todos.length : parsed.totalImported;
    if (recognized == 0) {
      if (!mounted || !effectiveOrigin.isCurrent()) return;
      final separator = DataSettingsUiCopy.isEn ? '; ' : '；';
      final warning = parsed.warnings.isEmpty
          ? ''
          : (DataSettingsUiCopy.isEn
                ? ': ${parsed.warnings.take(2).join(separator)}'
                : '：${parsed.warnings.take(2).join(separator)}');
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              DataSettingsUiCopy.noDataRecognized(tasksOnly, warning),
            ),
          ),
        );
      return;
    }

    final confirmed = await _confirmCompetitorImportPreview(
      draft: draft,
      parsed: parsed,
      tasksOnly: tasksOnly,
      origin: effectiveOrigin,
    );
    if (!mounted || !effectiveOrigin.isCurrent()) return;
    if (confirmed != true) return;

    if (effectiveOrigin.anniversaryOrigin?.isCurrent(checkRoute: false) ==
            false ||
        effectiveOrigin.countdownOrigin?.isCurrent(checkRoute: false) ==
            false) {
      return;
    }
    final anniversaryOperation =
        tasksOnly || effectiveOrigin.anniversaryOrigin == null
        ? null
        : DateItemOperation(effectiveOrigin.anniversaryOrigin!);
    final countdownOperation =
        tasksOnly || effectiveOrigin.countdownOrigin == null
        ? null
        : DateItemOperation(effectiveOrigin.countdownOrigin!);
    bool canWriteDates() =>
        effectiveOrigin.isCurrent() &&
        _isCurrentAction(currentSeq, currentGeneration) &&
        (anniversaryOperation?.isCurrent() ?? true) &&
        (countdownOperation?.isCurrent() ?? true);
    var dateApplyReleased = false;
    var actionBusyOccupied = false;
    _dismissActiveBanner();
    _currentRollbackToken = null;
    _competitorRollbackGeneration = null;
    setState(() {
      _busy = true;
      actionBusyOccupied = true;
    });
    try {
      if (!mounted || !canWriteDates()) return;
      final rollbackSnapshot = await BackupService.exportAll();
      if (!mounted || !canWriteDates()) return;
      final todoSummary = await effectiveOrigin.todoProvider.importTodos(
        parsed.todos,
      );
      if (!mounted || !canWriteDates()) return;
      final habitSummary = tasksOnly
          ? const HabitImportSummary(inserted: 0, skippedDuplicates: 0)
          : await effectiveOrigin.habitProvider.importHabits(parsed.habits);
      if (!mounted || !canWriteDates()) return;
      final noteSummary = tasksOnly
          ? const NoteImportSummary(inserted: 0, skippedDuplicates: 0)
          : await effectiveOrigin.noteProvider.importNotes(parsed.notes);
      if (!mounted || !canWriteDates()) return;
      final eventSummary = tasksOnly
          ? const CalendarEventImportSummary(inserted: 0, skippedDuplicates: 0)
          : await effectiveOrigin.calendarProvider.importLocalEvents(
              parsed.calendarEvents,
            );
      if (!mounted || !canWriteDates()) return;
      final anniversarySummary = tasksOnly
          ? const AnniversaryImportSummary(inserted: 0, skippedDuplicates: 0)
          : await effectiveOrigin.anniversaryProvider.importAnniversaries(
              parsed.anniversaries,
              canWrite: canWriteDates,
            );
      if (!mounted || !canWriteDates()) return;
      final countdownSummary = tasksOnly
          ? const CountdownImportSummary(inserted: 0, skippedDuplicates: 0)
          : await effectiveOrigin.countdownProvider.importCountdowns(
              parsed.countdowns,
              canWrite: canWriteDates,
            );
      if (!mounted || !canWriteDates()) return;
      final timeEntrySummary = tasksOnly
          ? const TimeEntryImportSummary(inserted: 0, skippedDuplicates: 0)
          : await effectiveOrigin.timeAuditProvider.importTimeEntries(
              parsed.timeEntries,
            );
      if (!mounted || !canWriteDates()) return;
      final rollbackToken = ++_rollbackTokenSeq;
      _currentRollbackToken = rollbackToken;
      _competitorRollbackGeneration = currentGeneration;
      setState(() => _busy = false);
      actionBusyOccupied = false;
      final summary = _CompetitorImportApplySummary(
        todoInserted: todoSummary.inserted,
        habitInserted: habitSummary.inserted,
        noteInserted: noteSummary.inserted,
        eventInserted: eventSummary.inserted,
        anniversaryInserted: anniversarySummary.inserted,
        countdownInserted: countdownSummary.inserted,
        timeEntryInserted: timeEntrySummary.inserted,
        skippedRows: parsed.skippedRows,
        skippedDuplicates:
            todoSummary.skippedDuplicates +
            habitSummary.skippedDuplicates +
            noteSummary.skippedDuplicates +
            eventSummary.skippedDuplicates +
            anniversarySummary.skippedDuplicates +
            countdownSummary.skippedDuplicates +
            timeEntrySummary.skippedDuplicates,
        reminderSyncIssues: [
          if (_nonEmptyImportReminderIssue(todoSummary.reminderSyncIssue)
              case final issue?)
            '${DataSettingsUiCopy.moduleTodo}: $issue',
          if (_nonEmptyImportReminderIssue(habitSummary.reminderSyncIssue)
              case final issue?)
            '${DataSettingsUiCopy.moduleHabit}: $issue',
          if (_nonEmptyImportReminderIssue(anniversarySummary.reminderSyncIssue)
              case final issue?)
            '${DataSettingsUiCopy.moduleAnniversary}: $issue',
          if (_nonEmptyImportReminderIssue(countdownSummary.reminderSyncIssue)
              case final issue?)
            '${DataSettingsUiCopy.moduleCountdown}: $issue',
        ],
      );
      if (!canWriteDates()) return;
      dateApplyReleased = true;
      anniversaryOperation?.dispose();
      countdownOperation?.dispose();
      final undo = await _showCompetitorImportResult(
        draft: draft,
        parsed: parsed,
        summary: summary,
        tasksOnly: tasksOnly,
        rollbackSnapshot: rollbackSnapshot,
        origin: effectiveOrigin,
      );
      if (!mounted || !effectiveOrigin.isCurrent()) return;
      if (undo == true) {
        ScaffoldMessenger.of(context).clearSnackBars();
        await _rollbackCompetitorImport(
          rollbackSnapshot,
          token: rollbackToken,
          accountGeneration: currentGeneration,
          origin: effectiveOrigin,
        );
      } else {
        _dismissActiveBanner();
        effectiveOrigin.markTransferred();
        final banner = _CompetitorRollbackBanner(
          token: rollbackToken,
          accountGeneration: currentGeneration,
          origin: effectiveOrigin,
        );
        _activeBanner = banner;
        final reminderIssueSuffix = summary.hasReminderSyncIssues
            ? DataSettingsUiCopy.partialRemindersSuffix
            : '';
        final importGeneration = currentGeneration;
        final boundToken = rollbackToken;
        ScaffoldMessenger.of(context).clearSnackBars();
        final controller = ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              DataSettingsUiCopy.importSuccessBanner(
                _competitorSourceLabel(draft.source),
                summary.inserted,
                summary.skipped,
                reminderIssueSuffix,
              ),
            ),
            action: SnackBarAction(
              label: DataSettingsUiCopy.undoImport,
              onPressed: () {
                if (!mounted || !effectiveOrigin.isCurrent()) return;
                _rollbackCompetitorImport(
                  rollbackSnapshot,
                  token: boundToken,
                  accountGeneration: importGeneration,
                  origin: effectiveOrigin,
                  banner: banner,
                );
              },
            ),
          ),
        );
        controller.closed.then((_) {
          if (identical(_activeBanner, banner)) {
            _activeBanner = null;
            if (_currentRollbackToken == boundToken) {
              _currentRollbackToken = null;
              _competitorRollbackGeneration = null;
            }
          }
          if (!banner.isConsumed) {
            banner.origin.dispose();
          }
        });
      }
    } catch (e) {
      if (!mounted ||
          (!dateApplyReleased && !canWriteDates()) ||
          e is AccountPreferenceWriteCanceled ||
          !effectiveOrigin.isCurrent()) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(DataSettingsUiCopy.formatDataMigrationError(e)),
          ),
        );
    } finally {
      anniversaryOperation?.dispose();
      countdownOperation?.dispose();
      if (origin == null && !effectiveOrigin.isTransferred) {
        effectiveOrigin.dispose();
      }
      if (actionBusyOccupied &&
          mounted &&
          _isCurrentAction(currentSeq, currentGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _confirmCompetitorImportPreview({
    required _CompetitorImportDraft draft,
    required CompetitorTaskImportResult parsed,
    required bool tasksOnly,
    required _CompetitorImportOrigin origin,
  }) async {
    var confirmed = false;
    final otherModuleCount = parsed.totalImported - parsed.todos.length;
    final previewRoute = createControllerDialogRoute<bool>(
      context: context,
      onRouteCreated: origin.registerOwnedRoute,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) {
            final samples = _competitorPreviewSamples(
              parsed,
              tasksOnly: tasksOnly,
            );
            return AppDialog(
              title: Text(DataSettingsUiCopy.importPreviewTitle),
              maxWidth: 600,
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DataSettingsUiCopy.importPreviewSource(
                        _competitorSourceLabel(draft.source),
                        parsed.sourceLabel,
                      ),
                    ),
                    if (!draft.fieldMapping.isEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        DataSettingsUiCopy.importPreviewMapping(
                          _fieldMappingSummary(draft.fieldMapping),
                        ),
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _importPreviewChip(
                          DataSettingsUiCopy.moduleTodo,
                          parsed.todos.length,
                        ),
                        _importPreviewChip(
                          DataSettingsUiCopy.moduleHabit,
                          parsed.habits.length,
                        ),
                        _importPreviewChip(
                          DataSettingsUiCopy.moduleNote,
                          parsed.notes.length,
                        ),
                        _importPreviewChip(
                          DataSettingsUiCopy.moduleEvent,
                          parsed.calendarEvents.length,
                        ),
                        _importPreviewChip(
                          DataSettingsUiCopy.moduleAnniversary,
                          parsed.anniversaries.length,
                        ),
                        _importPreviewChip(
                          DataSettingsUiCopy.moduleCountdown,
                          parsed.countdowns.length,
                        ),
                        _importPreviewChip(
                          DataSettingsUiCopy.moduleTimeEntry,
                          parsed.timeEntries.length,
                        ),
                        if (parsed.skippedRows > 0)
                          _importPreviewChip(
                            DataSettingsUiCopy.moduleSkippedRows,
                            parsed.skippedRows,
                          ),
                      ],
                    ),
                    if (tasksOnly && otherModuleCount > 0) ...[
                      const SizedBox(height: 12),
                      Text(
                        DataSettingsUiCopy.tasksOnlyNotice(otherModuleCount),
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      DataSettingsUiCopy.duplicatePolicyNotice,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    if (samples.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        DataSettingsUiCopy.sampleHeader,
                        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...samples
                          .take(6)
                          .map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('· $line'),
                            ),
                          ),
                    ],
                    if (parsed.warnings.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        DataSettingsUiCopy.warningHeader,
                        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...parsed.warnings
                          .take(4)
                          .map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('· $line'),
                            ),
                          ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: confirmed,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        DataSettingsUiCopy.confirmImportPolicyCheckbox,
                      ),
                      onChanged: (value) {
                        if (!ctx.mounted) return;
                        final route = ModalRoute.of(ctx);
                        if (route == null || !route.isCurrent) {
                          return;
                        }
                        if (!origin.isCurrent(currentModalRoute: route)) {
                          return;
                        }
                        setDialogState(() => confirmed = value == true);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (!ctx.mounted) return;
                    final route = ModalRoute.of(ctx);
                    if (route == null || !route.isCurrent) {
                      return;
                    }
                    Navigator.pop(ctx, false);
                  },
                  child: Text(I18n.tr('action.cancel')),
                ),
                FilledButton(
                  onPressed: confirmed
                      ? () {
                          if (!ctx.mounted) return;
                          final route = ModalRoute.of(ctx);
                          if (route == null || !route.isCurrent) {
                            return;
                          }
                          if (!origin.isCurrent(currentModalRoute: route)) {
                            return;
                          }
                          Navigator.pop(ctx, true);
                        }
                      : null,
                  child: Text(DataSettingsUiCopy.confirmImport),
                ),
              ],
            );
          },
        ),
      ),
    );
    final confirmedResult = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<bool>(previewRoute);
    await previewRoute.completed;
    return confirmedResult ?? false;
  }

  Future<bool> _showCompetitorImportResult({
    required _CompetitorImportDraft draft,
    required CompetitorTaskImportResult parsed,
    required _CompetitorImportApplySummary summary,
    required bool tasksOnly,
    required String rollbackSnapshot,
    required _CompetitorImportOrigin origin,
  }) async {
    assert(rollbackSnapshot.isNotEmpty);
    final separator = DataSettingsUiCopy.isEn ? '; ' : '；';
    final resultRoute = createControllerDialogRoute<bool>(
      context: context,
      onRouteCreated: origin.registerOwnedRoute,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => AppDialog(
          title: Text(DataSettingsUiCopy.importCompletedTitle),
          maxWidth: 560,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_competitorSourceLabel(draft.source)} · ${parsed.sourceLabel}',
              ),
              const SizedBox(height: 12),
              _importResultLine(
                DataSettingsUiCopy.moduleTodo,
                summary.todoInserted,
              ),
              if (!tasksOnly) ...[
                _importResultLine(
                  DataSettingsUiCopy.moduleHabit,
                  summary.habitInserted,
                ),
                _importResultLine(
                  DataSettingsUiCopy.moduleNote,
                  summary.noteInserted,
                ),
                _importResultLine(
                  DataSettingsUiCopy.moduleEvent,
                  summary.eventInserted,
                ),
                _importResultLine(
                  DataSettingsUiCopy.moduleAnniversary,
                  summary.anniversaryInserted,
                ),
                _importResultLine(
                  DataSettingsUiCopy.moduleCountdown,
                  summary.countdownInserted,
                ),
                _importResultLine(
                  DataSettingsUiCopy.moduleTimeEntry,
                  summary.timeEntryInserted,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                DataSettingsUiCopy.skippedSummary(
                  summary.skippedRows,
                  summary.skippedDuplicates,
                ),
              ),
              if (tasksOnly && parsed.totalImported > parsed.todos.length) ...[
                const SizedBox(height: 8),
                Text(DataSettingsUiCopy.tasksOnlyResultNotice),
              ],
              if (parsed.warnings.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${DataSettingsUiCopy.warningsPrefix}${parsed.warnings.take(2).join(separator)}',
                ),
              ],
              if (summary.hasReminderSyncIssues) ...[
                const SizedBox(height: 8),
                Text(
                  DataSettingsUiCopy.reminderNotFullyRegistered(
                    summary.reminderSyncIssues.take(2).join(separator),
                  ),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                ),
                if (summary.reminderSyncIssues.length > 2)
                  Text(
                    DataSettingsUiCopy.reminderMoreNeedResaving(
                      summary.reminderSyncIssues.length - 2,
                    ),
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Text(
                DataSettingsUiCopy.rollbackHint,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (!ctx.mounted) return;
                final route = ModalRoute.of(ctx);
                if (route == null || !route.isCurrent) {
                  return;
                }
                if (!origin.isCurrent(currentModalRoute: route)) {
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(DataSettingsUiCopy.undoImport),
            ),
            FilledButton(
              onPressed: () {
                if (!ctx.mounted) return;
                final route = ModalRoute.of(ctx);
                if (route == null || !route.isCurrent) {
                  return;
                }
                Navigator.pop(ctx, false);
              },
              child: Text(DataSettingsUiCopy.gotIt),
            ),
          ],
        ),
      ),
    );
    final undoResult = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<bool>(resultRoute);
    await resultRoute.completed;
    return undoResult ?? false;
  }

  Future<void> _rollbackCompetitorImport(
    String rollbackSnapshot, {
    int? token,
    int? accountGeneration,
    required _CompetitorImportOrigin origin,
    _CompetitorRollbackBanner? banner,
  }) async {
    if (!mounted || _busy) return;
    if (!origin.isCurrent()) {
      if (banner != null && identical(_activeBanner, banner)) {
        _dismissActiveBanner();
      } else {
        origin.dispose();
      }
      return;
    }
    final effectiveToken = token ?? _currentRollbackToken;
    final effectiveGeneration =
        accountGeneration ?? _competitorRollbackGeneration;
    if (effectiveToken == null ||
        _currentRollbackToken != effectiveToken ||
        effectiveGeneration == null ||
        _competitorRollbackGeneration != effectiveGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          effectiveGeneration,
        )) {
      if (banner != null && identical(_activeBanner, banner)) {
        _dismissActiveBanner();
      } else {
        origin.dispose();
      }
      return;
    }
    _currentRollbackToken = null;
    _competitorRollbackGeneration = null;
    if (banner != null && identical(_activeBanner, banner)) {
      banner.isConsumed = true;
      _activeBanner = null;
    }
    _activeRollbackOperations.add(origin);

    final todoProvider = origin.todoProvider;
    bool canWriteRollback() => mounted && origin.isCurrent();
    if (!canWriteRollback()) {
      _activeRollbackOperations.remove(origin);
      origin.dispose();
      return;
    }

    var rollbackBusyOccupied = false;
    setState(() {
      _busy = true;
      rollbackBusyOccupied = true;
    });
    try {
      if (!canWriteRollback()) return;
      await todoProvider.runExternalStorageUpdate(() async {
        if (!canWriteRollback()) return;
        await BackupService.importAll(
          rollbackSnapshot,
          merge: false,
          clearMissing: true,
          canWrite: canWriteRollback,
        );
      }, expectedAccountDataGeneration: effectiveGeneration);
      if (!canWriteRollback()) return;
      await Future.wait([
        origin.todoProvider.loadFromStorage(),
        origin.habitProvider.loadFromStorage(),
        origin.noteProvider.loadFromStorage(),
        origin.calendarProvider.loadFromStorage(),
        origin.anniversaryProvider.loadFromStorage(),
        origin.countdownProvider.loadFromStorage(),
        origin.timeAuditProvider.loadFromStorage(),
      ]);
      if (!mounted || !canWriteRollback()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.undoImportSuccess)),
      );
    } catch (e) {
      if (!mounted ||
          e is AccountPreferenceWriteCanceled ||
          !canWriteRollback()) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(DataSettingsUiCopy.formatRollbackError(e))),
        );
    } finally {
      _activeRollbackOperations.remove(origin);
      origin.dispose();
      if (rollbackBusyOccupied &&
          mounted &&
          _isCurrentAction(origin.seq, effectiveGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  String _competitorSourceLabel(_CompetitorImportSource source) {
    switch (source) {
      case _CompetitorImportSource.zhijianTime:
        return DataSettingsUiCopy.sourceZhijianTime;
      case _CompetitorImportSource.ticktick:
        return DataSettingsUiCopy.sourceTickTick;
      case _CompetitorImportSource.todoist:
        return DataSettingsUiCopy.sourceTodoist;
      case _CompetitorImportSource.generic:
        return DataSettingsUiCopy.sourceGeneric;
    }
  }

  String _competitorSourceHint(_CompetitorImportSource source) {
    switch (source) {
      case _CompetitorImportSource.zhijianTime:
        return DataSettingsUiCopy.hintZhijianTime;
      case _CompetitorImportSource.ticktick:
        return DataSettingsUiCopy.hintTickTick;
      case _CompetitorImportSource.todoist:
        return DataSettingsUiCopy.hintTodoist;
      case _CompetitorImportSource.generic:
        return DataSettingsUiCopy.hintGeneric;
    }
  }

  Future<CompetitorFieldMapping?> _editCompetitorFieldMapping(
    CompetitorFieldMapping initial, {
    _CompetitorImportOrigin? origin,
    ModalRoute<dynamic>? parentRoute,
  }) async {
    final controllers = <String, TextEditingController>{
      for (final target in _competitorFieldMappingTargets)
        target.$1: TextEditingController(text: initial.sourceFor(target.$1)),
    };
    return await showControllerDialog<CompetitorFieldMapping>(
      context: context,
      controllers: [...controllers.values],
      onRouteCreated: origin?.registerOwnedRoute,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => AppDialog(
          title: Text(DataSettingsUiCopy.advancedFieldMapping),
          maxWidth: 680,
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DataSettingsUiCopy.advancedFieldMappingHint,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  for (final target in _competitorFieldMappingTargets) ...[
                    TextField(
                      controller: controllers[target.$1],
                      decoration: InputDecoration(
                        labelText: DataSettingsUiCopy.fieldTargetLabel(
                          target.$1,
                        ),
                        hintText: DataSettingsUiCopy.sourceFieldNameHint,
                        helperText: DataSettingsUiCopy.standardFieldHelper(
                          target.$1,
                        ),
                        helperMaxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (!ctx.mounted) return;
                final route = ModalRoute.of(ctx);
                if (route == null || !route.isCurrent) {
                  return;
                }
                if ((parentRoute != null && !parentRoute.isActive) ||
                    (origin != null &&
                        !origin.isCurrent(currentModalRoute: route))) {
                  return;
                }
                for (final controller in controllers.values) {
                  controller.clear();
                }
              },
              child: Text(I18n.tr('action.clear')),
            ),
            TextButton(
              onPressed: () {
                if (!ctx.mounted) return;
                final route = ModalRoute.of(ctx);
                if (route == null || !route.isCurrent) {
                  return;
                }
                Navigator.pop(ctx);
              },
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (!ctx.mounted) return;
                final route = ModalRoute.of(ctx);
                if (route == null || !route.isCurrent) {
                  return;
                }
                if ((parentRoute != null && !parentRoute.isActive) ||
                    (origin != null &&
                        !origin.isCurrent(currentModalRoute: route))) {
                  Navigator.pop(ctx);
                  return;
                }
                Navigator.pop(
                  ctx,
                  CompetitorFieldMapping({
                    for (final target in _competitorFieldMappingTargets)
                      if (controllers[target.$1]!.text.trim().isNotEmpty)
                        target.$1: controllers[target.$1]!.text.trim(),
                  }),
                );
              },
              child: Text(I18n.tr('action.save')),
            ),
          ],
        ),
      ),
    );
  }

  String _fieldMappingSummary(CompetitorFieldMapping fieldMapping) {
    final entries = fieldMapping.targetToSource.entries
        .where(
          (entry) =>
              entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
        )
        .toList();
    if (entries.isEmpty) return DataSettingsUiCopy.fieldMappingNone;
    final separator = DataSettingsUiCopy.isEn ? ', ' : '，';
    final preview = entries
        .take(3)
        .map(
          (entry) => '${_fieldMappingTargetLabel(entry.key)} <- ${entry.value}',
        )
        .join(separator);
    if (entries.length <= 3) return preview;
    return '$preview${DataSettingsUiCopy.fieldMappingMoreItems(entries.length - 3)}';
  }

  String _fieldMappingTargetLabel(String key) {
    return DataSettingsUiCopy.fieldTargetLabel(key);
  }

  Widget _importPreviewChip(String label, int count) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label $count'),
      backgroundColor: count > 0
          ? cs.primaryContainer.withValues(alpha: 0.72)
          : cs.surfaceContainerHighest.withValues(alpha: 0.52),
      side: BorderSide(
        color: count > 0
            ? cs.primary.withValues(alpha: 0.28)
            : cs.outlineVariant,
      ),
    );
  }

  Widget _importResultLine(String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(DataSettingsUiCopy.itemCount(count)),
        ],
      ),
    );
  }

  String? _nonEmptyImportReminderIssue(String? issue) {
    final trimmed = issue?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  List<String> _competitorPreviewSamples(
    CompetitorTaskImportResult parsed, {
    required bool tasksOnly,
  }) {
    final samples = <String>[];
    samples.addAll(
      parsed.todos
          .take(3)
          .map(
            (todo) =>
                '${DataSettingsUiCopy.moduleTodo}: ${_shortImportText(todo.title)}',
          ),
    );
    if (!tasksOnly) {
      samples.addAll(
        parsed.habits
            .take(2)
            .map(
              (habit) =>
                  '${DataSettingsUiCopy.moduleHabit}: ${_shortImportText(habit.name)}',
            ),
      );
      samples.addAll(
        parsed.notes
            .take(2)
            .map(
              (note) =>
                  '${DataSettingsUiCopy.moduleNote}: ${_shortImportText(note.content)}',
            ),
      );
      samples.addAll(
        parsed.calendarEvents
            .take(2)
            .map(
              (event) =>
                  '${DataSettingsUiCopy.moduleEvent}: ${_shortImportText(event.title)}',
            ),
      );
      samples.addAll(
        parsed.anniversaries
            .take(2)
            .map(
              (item) =>
                  '${DataSettingsUiCopy.moduleAnniversary}: ${_shortImportText(item.title)}',
            ),
      );
      samples.addAll(
        parsed.countdowns
            .take(2)
            .map(
              (item) =>
                  '${DataSettingsUiCopy.moduleCountdown}: ${_shortImportText(item.title)}',
            ),
      );
      samples.addAll(
        parsed.timeEntries
            .take(2)
            .map(
              (entry) =>
                  '${DataSettingsUiCopy.moduleTimeEntry}: ${_shortImportText(entry.title)}',
            ),
      );
    }
    return samples
        .where((line) => !line.endsWith(': ') && !line.endsWith('：'))
        .toList();
  }

  String _shortImportText(String value) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= 32) return compact;
    return '${compact.substring(0, 32)}...';
  }

  Future<void> _wipe() async {
    final todoProvider = context.read<TodoProvider>();
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final seq = ++_actionSeq;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => AppDialog(
          title: Text(DataSettingsUiCopy.wipeDialogTitle),
          content: Text(DataSettingsUiCopy.wipeDialogContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(DataSettingsUiCopy.wipeButton),
            ),
          ],
        ),
      ),
    );
    if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
    if (ok != true) return;

    _currentRollbackToken = null;
    _competitorRollbackGeneration = null;
    setState(() => _busy = true);
    try {
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      await todoProvider.runExternalStorageUpdate(
        () async => await BackupService.wipeAll(),
        expectedAccountDataGeneration: accountGeneration,
      );
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      _currentRollbackToken = null;
      _competitorRollbackGeneration = null;
      await _reloadAll(accountGeneration: accountGeneration, seq: seq);
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(DataSettingsUiCopy.wipeSuccess)));
    } catch (e) {
      if (!mounted ||
          e is AccountPreferenceWriteCanceled ||
          !_isCurrentAction(seq, accountGeneration)) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_formatWipeError(e))));
    } finally {
      if (mounted && _isCurrentAction(seq, accountGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _configureWebDavBackup() async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final seq = ++_actionSeq;
    final baseCtrl = TextEditingController(text: _webDavConfig.baseUrl);
    final userCtrl = TextEditingController(text: _webDavConfig.username);
    final passwordCtrl = TextEditingController(text: _webDavConfig.password);
    final pathCtrl = TextEditingController(text: _webDavConfig.remotePath);
    final fileCtrl = TextEditingController(text: _webDavConfig.filename);
    final saved = await showControllerDialog<bool>(
      context: context,
      controllers: [baseCtrl, userCtrl, passwordCtrl, pathCtrl, fileCtrl],
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => AppDialog(
          title: Text(DataSettingsUiCopy.webDavDialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: baseCtrl,
                  decoration: const InputDecoration(
                    labelText: 'WebDAV URL',
                    hintText: 'https://dav.example.com/dav',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: userCtrl,
                  decoration: InputDecoration(
                    labelText: DataSettingsUiCopy.webDavUsername,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: DataSettingsUiCopy.webDavPassword,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pathCtrl,
                  decoration: InputDecoration(
                    labelText: DataSettingsUiCopy.webDavRemotePath,
                    hintText: '/duoyi-backups',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: fileCtrl,
                  decoration: InputDecoration(
                    labelText: DataSettingsUiCopy.webDavFilename,
                    hintText: 'duoyi-latest.json',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(I18n.tr('action.save')),
            ),
          ],
        ),
      ),
    );
    if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
    if (saved != true) return;
    final config = WebDavBackupConfig(
      baseUrl: baseCtrl.text.trim(),
      username: userCtrl.text.trim(),
      password: passwordCtrl.text,
      remotePath: pathCtrl.text.trim().isEmpty
          ? '/duoyi-backups'
          : pathCtrl.text.trim(),
      filename: fileCtrl.text.trim().isEmpty
          ? 'duoyi-latest.json'
          : fileCtrl.text.trim(),
    );
    try {
      await WebDavBackupService.saveConfig(config);
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      setState(() => _webDavConfig = config);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) =>
                Text(DataSettingsUiCopy.webDavConfigSaved),
          ),
        ),
      );
    } catch (e) {
      if (!mounted ||
          e is AccountPreferenceWriteCanceled ||
          !_isCurrentAction(seq, accountGeneration)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) =>
                Text(DataSettingsUiCopy.formatWebDavSaveError(e)),
          ),
        ),
      );
    }
  }

  Future<void> _uploadWebDavBackup() async {
    var accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    if (!_webDavConfig.isConfigured) {
      await _configureWebDavBackup();
      if (!mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          ) ||
          !_webDavConfig.isConfigured) {
        return;
      }
    }
    accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final seq = ++_actionSeq;
    final targetConfig = _webDavConfig;
    setState(() => _busy = true);
    try {
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      final result = await WebDavBackupService().uploadCurrentBackup(
        targetConfig,
      );
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      final sanitizedUri = _sanitizeUriForDisplay(result.uri);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            DataSettingsUiCopy.webDavUploadSuccess(
              result.bytes / 1024,
              sanitizedUri,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted ||
          e is AccountPreferenceWriteCanceled ||
          !_isCurrentAction(seq, accountGeneration)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatWebDavUploadError(e))),
      );
    } finally {
      if (mounted && _isCurrentAction(seq, accountGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  String _sanitizeUriForDisplay(Uri uri) {
    if (uri.userInfo.isNotEmpty) {
      return uri.replace(userInfo: '').toString();
    }
    return uri.toString();
  }

  String _sanitizeUrlString(String raw) {
    try {
      final parsed = Uri.parse(raw);
      if (parsed.userInfo.isNotEmpty) {
        return parsed.replace(userInfo: '').toString();
      }
    } catch (_) {}
    return raw;
  }

  Future<void> _restoreFromWebDav({required bool merge}) async {
    var accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    if (!_webDavConfig.isConfigured) {
      await _configureWebDavBackup();
      if (!mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          ) ||
          !_webDavConfig.isConfigured) {
        return;
      }
    }
    final todoProvider = context.read<TodoProvider>();
    accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final seq = ++_actionSeq;
    final targetConfig = _webDavConfig;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => AppDialog(
          title: Text(DataSettingsUiCopy.webDavRestoreDialogTitle(merge)),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DataSettingsUiCopy.webDavRestoreDesc(
                  merge,
                  targetConfig.filename,
                ),
              ),
              // 覆盖恢复同样真删数据：写明缺失数据将被删除的后果。
              if (!merge) ...[
                const SizedBox(height: 8),
                Text(
                  I18n.tr('backup.overwrite.will_delete_missing'),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(DataSettingsUiCopy.startRestore),
            ),
          ],
        ),
      ),
    );
    if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
    if (ok != true) return;
    _currentRollbackToken = null;
    _competitorRollbackGeneration = null;
    setState(() => _busy = true);
    try {
      final raw = await WebDavBackupService().downloadLatestBackup(
        targetConfig,
      );
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      final count = await todoProvider.runExternalStorageUpdate(
        () async => await BackupService.importAll(
          raw,
          merge: merge,
          // 覆盖=还原到备份快照：备份中不存在的本机数据一并删除，弹窗已警告。
          // 服务层 `clearMissing && !merge` 守卫保证 merge 合并入口不受影响。
          clearMissing: true,
        ),
        expectedAccountDataGeneration: accountGeneration,
      );
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      _currentRollbackToken = null;
      _competitorRollbackGeneration = null;
      await _reloadAll(accountGeneration: accountGeneration, seq: seq);
      if (!mounted || !_isCurrentAction(seq, accountGeneration)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(DataSettingsUiCopy.webDavRestoreSuccess(merge, count)),
        ),
      );
    } catch (e) {
      if (!mounted ||
          e is AccountPreferenceWriteCanceled ||
          !_isCurrentAction(seq, accountGeneration)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatWebDavRestoreError(e))),
      );
    } finally {
      if (mounted && _isCurrentAction(seq, accountGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _reloadAll({int? accountGeneration, int? seq}) async {
    bool isCurrent() {
      if (!mounted) return false;
      if (accountGeneration != null &&
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          )) {
        return false;
      }
      if (seq != null && seq != _actionSeq) return false;
      return true;
    }

    if (!isCurrent()) return;

    final preferencesProvider = context.read<PreferencesProvider>();
    final achievementProvider = context.read<AchievementProvider>();
    final todoProvider = context.read<TodoProvider>();
    final habitProvider = context.read<HabitProvider>();
    final pomodoroProvider = context.read<PomodoroProvider>();
    final noteProvider = context.read<NoteProvider>();
    final anniversaryProvider = context.read<AnniversaryProvider>();
    final diaryProvider = context.read<DiaryProvider>();
    final goalProvider = context.read<GoalProvider>();
    final courseProvider = context.read<CourseProvider>();
    final userProvider = context.read<UserProvider>();
    final timeAuditProvider = context.read<TimeAuditProvider>();
    final shareProvider = context.read<ShareProvider>();
    final calendarProvider = context.read<CalendarProvider>();
    final countdownProvider = context.read<CountdownProvider>();
    final locationReminderProvider = context.read<LocationReminderProvider>();
    final quickCaptureTemplateProvider = context
        .read<QuickCaptureTemplateProvider>();

    // 偏好键已纳入备份键集（BackupService._keys）：wipeAll/importAll 都会
    // 改写偏好存储，而根级 PreferencesProvider 的值缓存在内存字段，不重载
    // 会造成进程内偏好与存储分叉。与 main.dart 账号清理/云同步拉取一致：
    // 先 resetLocalState 作废在途读取并套用默认值，再 loadFromStorage 读回
    // 存储真值，最后把铃声偏好重放到原生设置（非 Android 为 no-op）。
    // AchievementProvider 类似地会合并在途读取，需先 resetLocalState 作废旧读取。
    preferencesProvider.resetLocalState();
    if (!isCurrent()) return;
    achievementProvider.resetLocalState();
    if (!isCurrent()) return;

    await preferencesProvider.loadFromStorage();
    if (!isCurrent()) return;

    await ReminderRingtoneSettings.applyPersistedSettingsToNative();
    if (!isCurrent()) return;

    await Future.wait([
      todoProvider.loadFromStorage(),
      habitProvider.loadFromStorage(),
      pomodoroProvider.loadFromStorage(),
      noteProvider.loadFromStorage(),
      anniversaryProvider.loadFromStorage(),
      diaryProvider.loadFromStorage(),
      goalProvider.loadFromStorage(),
      courseProvider.loadFromStorage(),
      userProvider.loadFromStorage(),
      timeAuditProvider.loadFromStorage(),
      achievementProvider.loadFromStorage(),
      shareProvider.load(),
      calendarProvider.loadFromStorage(),
      countdownProvider.loadFromStorage(),
      locationReminderProvider.loadFromStorage(),
      quickCaptureTemplateProvider.loadFromStorage(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final cs = Theme.of(context).colorScheme;
        final routeBackground = Theme.of(context).brightness == Brightness.dark
            ? cs.surface
            : cs.surfaceContainerLowest;
        final surfaceStyle = appSurfaceStyleOf(context);
        final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
        final restoreFirst = widget.initialMode == BackupEntryMode.restore;
        final pageTitle = DataSettingsUiCopy.backupHeroTitle(restoreFirst);
        final scaffold = Scaffold(
          backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
          appBar: AppBar(
            title: Text(pageTitle),
            titleTextStyle: appSecondaryRouteTitleTextStyle(context),
            backgroundColor: routeBackground.withValues(alpha: 0.96),
            surfaceTintColor: Colors.transparent,
          ),
          body: AppSecondaryControlTheme(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              children: [
                AppSurfaceCard(
                  padding: const EdgeInsets.all(16),
                  gradient: LinearGradient(
                    colors: [cs.primary.withValues(alpha: 0.12), cs.surface],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.backup_outlined,
                          color: cs.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pageTitle,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.normal,
                                    color: cs.onSurface,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DataSettingsUiCopy.backupHeroSubtitle(
                                restoreFirst,
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.66),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (restoreFirst) ...[
                  _restoreSection(),
                  const SizedBox(height: 12),
                  _backupSection(),
                ] else ...[
                  _backupSection(),
                  const SizedBox(height: 12),
                  _restoreSection(),
                ],
                const SizedBox(height: 12),
                _webDavBackupSection(),
                const SizedBox(height: 12),
                AppSettingsSection(
                  title: DataSettingsUiCopy.singleModuleExportTitle,
                  subtitle: DataSettingsUiCopy.singleModuleExportSubtitle,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chip(DataSettingsUiCopy.exportChipTodoCsv, () {
                          final todos = context.read<TodoProvider>().todos;
                          _showExport(
                            _ExportKind.todosCsv,
                            ModuleExporter.todosCsv(todos),
                          );
                        }),
                        _chip(DataSettingsUiCopy.exportChipTodoMd, () {
                          final todos = context.read<TodoProvider>().todos;
                          _showExport(
                            _ExportKind.todosMd,
                            ModuleExporter.todosMarkdown(todos),
                          );
                        }),
                        _chip(DataSettingsUiCopy.exportChipHabitCsv, () {
                          final hs = context.read<HabitProvider>().habits;
                          _showExport(
                            _ExportKind.habitsCsv,
                            ModuleExporter.habitsCsv(hs),
                          );
                        }),
                        _chip(DataSettingsUiCopy.exportChipTimeEntryCsv, () {
                          final entries = context
                              .read<TimeAuditProvider>()
                              .entries;
                          _showExport(
                            _ExportKind.timeEntriesCsv,
                            ModuleExporter.timeEntriesCsv(entries),
                          );
                        }),
                        _chip(DataSettingsUiCopy.exportChipNoteCsv, () {
                          final ns = context.read<NoteProvider>().notes;
                          _showExport(
                            _ExportKind.notesCsv,
                            ModuleExporter.notesCsv(ns),
                          );
                        }),
                        _chip(DataSettingsUiCopy.exportChipNoteMd, () {
                          final ns = context.read<NoteProvider>().notes;
                          _showExport(
                            _ExportKind.notesMd,
                            ModuleExporter.notesMarkdown(ns),
                          );
                        }),
                        _chip(DataSettingsUiCopy.exportChipDiaryMd, () {
                          final ds = context.read<DiaryProvider>().entries;
                          _showExport(
                            _ExportKind.diaryMd,
                            ModuleExporter.diaryMarkdown(ds),
                          );
                        }),
                        _chip(DataSettingsUiCopy.exportChipDiaryCsv, () {
                          final ds = context.read<DiaryProvider>().entries;
                          _showExport(
                            _ExportKind.diaryCsv,
                            ModuleExporter.diaryCsv(ds),
                          );
                        }),
                        _chip(DataSettingsUiCopy.exportChipAnniversaryCsv, () {
                          final list = context
                              .read<AnniversaryProvider>()
                              .items;
                          _showExport(
                            _ExportKind.anniversariesCsv,
                            ModuleExporter.anniversariesCsv(list),
                          );
                        }),
                        _chip(DataSettingsUiCopy.exportChipAnniversaryMd, () {
                          final list = context
                              .read<AnniversaryProvider>()
                              .items;
                          _showExport(
                            _ExportKind.anniversariesMd,
                            ModuleExporter.anniversariesMarkdown(list),
                          );
                        }),
                        _chip(DataSettingsUiCopy.exportChipGoalCsv, () {
                          final list = context.read<GoalProvider>().goals;
                          _showExport(
                            _ExportKind.goalsCsv,
                            ModuleExporter.goalsCsv(list),
                          );
                        }),
                        _chip(DataSettingsUiCopy.exportChipGoalMd, () {
                          final list = context.read<GoalProvider>().goals;
                          _showExport(
                            _ExportKind.goalsMd,
                            ModuleExporter.goalsMarkdown(list),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
                if (_exported != null) ...[
                  const SizedBox(height: 12),
                  AppSurfaceCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _activeExportedTitle(),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.normal,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            TextButton.icon(
                              onPressed: _busy ? null : _copy,
                              icon: const Icon(Icons.copy, size: 14),
                              label: Text(DataSettingsUiCopy.copyButton),
                            ),
                            TextButton.icon(
                              key: const ValueKey('backup_download_exported'),
                              onPressed: _busy ? null : _downloadExported,
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 14,
                              ),
                              label: Text(
                                I18n.current == AppLocale.en
                                    ? 'Download file'
                                    : '下载文件',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          height: 200,
                          width: double.infinity,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              _exported!,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                AppSettingsSection(
                  title: DataSettingsUiCopy.dangerZoneTitle,
                  subtitle: DataSettingsUiCopy.dangerZoneSubtitle,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _wipe,
                      icon: Icon(Icons.delete_forever, color: cs.error),
                      label: Text(
                        DataSettingsUiCopy.wipeButton,
                        style: TextStyle(color: cs.error),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: cs.error.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
      },
    );
  }

  Widget _chip(String label, VoidCallback onTap) {
    return ActionChip(
      avatar: const Icon(Icons.download, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: _busy ? null : onTap,
    );
  }

  Widget _backupSection() {
    return AppSettingsSection(
      title: DataSettingsUiCopy.backupSectionTitle,
      subtitle: DataSettingsUiCopy.backupSectionSubtitle,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _exportAll,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: Text(DataSettingsUiCopy.generateJsonButton),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('backup_download_json'),
            onPressed: _busy ? null : _exportAndDownloadAllJson,
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: Text(
              I18n.current == AppLocale.en
                  ? 'Export & download .json file'
                  : '导出并下载 .json 文件',
            ),
          ),
        ),
      ],
    );
  }

  Widget _webDavBackupSection() {
    final configured = _webDavConfig.isConfigured;
    final sanitizedBase = _sanitizeUrlString(_webDavConfig.baseUrl);
    final subtitle = configured
        ? '$sanitizedBase · ${_webDavConfig.remotePath}/${_webDavConfig.filename}'
        : DataSettingsUiCopy.webDavSubtitleNotConfigured;
    return AppSettingsSection(
      title: DataSettingsUiCopy.webDavSectionTitle,
      subtitle: subtitle,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow =
                constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(14) > 17;
            final configBtn = OutlinedButton.icon(
              onPressed: _busy ? null : _configureWebDavBackup,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: Text(
                DataSettingsUiCopy.webDavConfigureButton(configured),
                overflow: TextOverflow.ellipsis,
              ),
            );
            final uploadBtn = FilledButton.icon(
              onPressed: _busy ? null : _uploadWebDavBackup,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text(
                DataSettingsUiCopy.webDavUploadButton,
                overflow: TextOverflow.ellipsis,
              ),
            );
            final mergeBtn = OutlinedButton.icon(
              onPressed: _busy ? null : () => _restoreFromWebDav(merge: true),
              icon: const Icon(Icons.cloud_sync_outlined, size: 18),
              label: Text(
                DataSettingsUiCopy.webDavMergeButton,
                overflow: TextOverflow.ellipsis,
              ),
            );
            final overwriteBtn = OutlinedButton.icon(
              onPressed: _busy ? null : () => _restoreFromWebDav(merge: false),
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(
                DataSettingsUiCopy.webDavOverwriteButton,
                overflow: TextOverflow.ellipsis,
              ),
            );

            if (isNarrow) {
              return Column(
                children: [
                  SizedBox(width: double.infinity, child: configBtn),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: uploadBtn),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: mergeBtn),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: overwriteBtn),
                ],
              );
            }
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: configBtn),
                    const SizedBox(width: 8),
                    Expanded(child: uploadBtn),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: mergeBtn),
                    const SizedBox(width: 8),
                    Expanded(child: overwriteBtn),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _restoreSection() {
    return AppSettingsSection(
      title: DataSettingsUiCopy.restoreSectionTitle,
      subtitle: DataSettingsUiCopy.restoreSectionSubtitle,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow =
                constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(14) > 17;
            final mergeBtn = OutlinedButton.icon(
              onPressed: _busy ? null : () => _import(merge: true),
              icon: const Icon(Icons.merge, size: 18),
              label: Text(
                DataSettingsUiCopy.mergeImportButton,
                overflow: TextOverflow.ellipsis,
              ),
            );
            final overwriteBtn = OutlinedButton.icon(
              onPressed: _busy ? null : () => _import(merge: false),
              icon: const Icon(Icons.upload, size: 18),
              label: Text(
                DataSettingsUiCopy.overwriteImportButton,
                overflow: TextOverflow.ellipsis,
              ),
            );
            final fileMergeBtn = OutlinedButton.icon(
              onPressed: _busy ? null : () => _importBackupFile(merge: true),
              icon: const Icon(Icons.file_open_outlined, size: 18),
              label: Text(
                DataSettingsUiCopy.fileMergeButton,
                overflow: TextOverflow.ellipsis,
              ),
            );
            final fileOverwriteBtn = OutlinedButton.icon(
              onPressed: _busy ? null : () => _importBackupFile(merge: false),
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: Text(
                DataSettingsUiCopy.fileOverwriteButton,
                overflow: TextOverflow.ellipsis,
              ),
            );

            return Column(
              children: [
                if (isNarrow) ...[
                  SizedBox(width: double.infinity, child: mergeBtn),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: overwriteBtn),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: fileMergeBtn),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: fileOverwriteBtn),
                ] else ...[
                  Row(
                    children: [
                      Expanded(child: mergeBtn),
                      const SizedBox(width: 8),
                      Expanded(child: overwriteBtn),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: fileMergeBtn),
                      const SizedBox(width: 8),
                      Expanded(child: fileOverwriteBtn),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _importTasksFromOtherApps,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.move_to_inbox_outlined, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            DataSettingsUiCopy.importTasksFromOtherAppsButton,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : _importProductivityDataFromOtherApps,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.input_outlined, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            DataSettingsUiCopy
                                .importProductivityFromOtherAppsButton,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _importProductivityDataFile,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.upload_file_outlined, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            DataSettingsUiCopy.importProductivityFileButton,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
