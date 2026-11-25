import 'dart:async' show Timer;
import 'dart:math' as math;

import '../widgets/app_date_format.dart';
import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/time_audit_ui_copy.dart';
import '../models/time_entry.dart';
import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/time_audit_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/app_update_service.dart';
import '../services/ics_exporter.dart';
import '../services/web_file_download.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/brand_background.dart';
import '../widgets/controller_dialog.dart' show showControllerDialog;
import '../widgets/surface_components.dart';

enum _AuditRange { today, week, month, all }

enum _AuditView { timeline, category, calendar, trend }

class _TimeAuditOrigin {
  _TimeAuditOrigin._({
    required this.provider,
    required this.storageGeneration,
    required this.accountGeneration,
    required this.auth,
    required this.route,
    required this.sessionLease,
    required this.leaseFailed,
  }) : sessionGeneration = auth?.sessionGeneration,
       wasLoggedIn = auth?.state.isLoggedIn ?? false,
       _userId = _normalize(auth?.state.userId);

  final TimeAuditProvider provider;
  final int storageGeneration;
  final int accountGeneration;
  final AuthProvider? auth;
  final ModalRoute<dynamic>? route;
  final AuthSessionLease? sessionLease;
  final bool leaseFailed;
  final int? sessionGeneration;
  final bool wasLoggedIn;
  String? _userId;

  static String? _normalize(String? raw) {
    final value = raw?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static T? _readOptional<T extends Object>(BuildContext context) {
    try {
      return context.read<T?>();
    } catch (_) {
      return null;
    }
  }

  static _TimeAuditOrigin capture(
    BuildContext context, {
    ModalRoute<dynamic>? route,
  }) {
    final provider = context.read<TimeAuditProvider>();
    final auth = _readOptional<AuthProvider>(context);
    AuthSessionLease? lease;
    var failed = false;
    if (auth?.state.isLoggedIn == true) {
      try {
        lease = auth!.captureSessionLease();
      } catch (_) {
        failed = true;
      }
    }
    return _TimeAuditOrigin._(
      provider: provider,
      storageGeneration: provider.storageGeneration,
      accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
      auth: auth,
      route: route ?? ModalRoute.of(context),
      sessionLease: lease,
      leaseFailed: failed,
    );
  }

  bool isCurrent(
    BuildContext context, {
    bool checkRoute = true,
    bool checkAccess = true,
  }) {
    if (!context.mounted ||
        leaseFailed ||
        provider.isDisposed ||
        provider.storageGeneration != storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return false;
    }
    if (route != null &&
        (!route!.isActive || (checkRoute && !route!.isCurrent))) {
      return false;
    }
    try {
      TimeAuditProvider? currentProvider;
      try {
        currentProvider = context.read<TimeAuditProvider>();
      } catch (_) {
        return false;
      }
      if (!identical(currentProvider, provider)) {
        return false;
      }
      final currentAuth = _readOptional<AuthProvider>(context);
      if (!identical(currentAuth, auth)) {
        return false;
      }
      if (currentAuth != null) {
        if (currentAuth.sessionGeneration != sessionGeneration ||
            currentAuth.state.isLoggedIn != wasLoggedIn ||
            currentAuth.isAccountTransitionInProgress ||
            currentAuth.isLocalAccountDataBlocked ||
            (sessionLease != null &&
                !currentAuth.isSessionLeaseCurrent(sessionLease!))) {
          return false;
        }
        final id = _normalize(currentAuth.state.userId);
        if (_userId != null && id != _userId) return false;
        _userId ??= id;
      }
      if (checkAccess) {
        final lock = _readOptional<AppLockProvider>(context);
        final update = _readOptional<AppUpdateService>(context);
        if (lock?.isLocked == true || update?.mustUpdate == true) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

class TimeAuditScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final String? initialEntryId;
  final bool openInitialEntrySheet;

  const TimeAuditScreen({
    super.key,
    this.initialEntryId,
    this.openInitialEntrySheet = true,
  });

  @override
  State<TimeAuditScreen> createState() => _TimeAuditScreenState();
}

class _TimeAuditScreenState extends State<TimeAuditScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _entryKeys = <String, GlobalKey>{};
  _AuditRange _range = _AuditRange.today;
  _AuditView _view = _AuditView.timeline;
  bool _openedInitialEntry = false;
  _TimeAuditOrigin? _initialOrigin;
  String? _highlightedEntryId;
  String? _scrolledEntryId;

  Timer? _stopwatchTimer;
  bool _stopwatchRunning = false;
  final ValueNotifier<int> _stopwatchElapsedSeconds = ValueNotifier<int>(0);
  int _stopwatchAccumulatedSeconds = 0;
  DateTime? _stopwatchSegmentStartedAt;
  TimeEntryCategory _stopwatchCategory = TimeEntryCategory.focus;
  String _stopwatchCustomTitle = '';

  @override
  void initState() {
    super.initState();
    _highlightedEntryId = widget.initialEntryId;
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  @override
  void didUpdateWidget(covariant TimeAuditScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialEntryId != widget.initialEntryId ||
        oldWidget.openInitialEntrySheet != widget.openInitialEntrySheet) {
      _openedInitialEntry = false;
      _highlightedEntryId = widget.initialEntryId;
      _scrolledEntryId = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initialOrigin ??= _TimeAuditOrigin.capture(context);
  }

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    _stopwatchElapsedSeconds.dispose();
    _scrollController.dispose();
    I18n.localeListenable.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  GlobalKey _keyForEntry(String id) =>
      _entryKeys.putIfAbsent(id, () => GlobalKey());

  void _scheduleHighlightScroll(List<TimeEntry> entries) {
    final id = _highlightedEntryId;
    if (id == null || id.isEmpty || _scrolledEntryId == id) return;
    if (!entries.any((e) => e.id == id)) return;
    _scrolledEntryId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _entryKeys[id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 220),
          alignment: 0.2,
        );
      }
    });
  }

  void _openInitialEntryIfNeeded(TimeAuditProvider provider) {
    if (_openedInitialEntry) return;
    final initialOrigin = _initialOrigin;
    if (initialOrigin == null ||
        !initialOrigin.isCurrent(context, checkRoute: false)) {
      _openedInitialEntry = true;
      return;
    }
    final id = widget.initialEntryId;
    if (id == null || id.isEmpty) {
      _openedInitialEntry = true;
      return;
    }
    final hasEntry = provider.entries.any((entry) => entry.id == id);
    if (!hasEntry) return;
    _openedInitialEntry = true;
    _highlightedEntryId = id;
    if (_range != _AuditRange.all) {
      _range = _AuditRange.all;
      _view = _AuditView.timeline;
    }
    if (!widget.openInitialEntrySheet) return;
    final scheduledOrigin = initialOrigin;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isActive) return;
      if (!scheduledOrigin.isCurrent(context, checkRoute: false)) return;
      final currentEntry = scheduledOrigin.provider.entries
          .where((entry) => entry.id == id)
          .firstOrNull;
      if (currentEntry == null) return;
      _showEditor(context, scheduledOrigin, entry: currentEntry);
    });
  }

  void _startOrResumeStopwatch() {
    if (_stopwatchRunning) return;
    _stopwatchTimer?.cancel();
    setState(() {
      _stopwatchRunning = true;
      _stopwatchAccumulatedSeconds = _stopwatchElapsedSeconds.value;
      _stopwatchSegmentStartedAt = DateTime.now();
    });
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_stopwatchRunning) return;
      var next = _stopwatchElapsedSeconds.value + 1;
      final started = _stopwatchSegmentStartedAt;
      if (started != null) {
        final wallTotal =
            _stopwatchAccumulatedSeconds +
            DateTime.now().difference(started).inSeconds;
        if (wallTotal > next) {
          next = wallTotal;
        }
      }
      _stopwatchElapsedSeconds.value = next;
    });
  }

  void _pauseStopwatch() {
    if (!_stopwatchRunning) return;
    _stopwatchTimer?.cancel();
    _stopwatchTimer = null;
    setState(() {
      _stopwatchRunning = false;
      _stopwatchAccumulatedSeconds = _stopwatchElapsedSeconds.value;
      _stopwatchSegmentStartedAt = null;
    });
  }

  void _resetStopwatch() {
    _stopwatchTimer?.cancel();
    _stopwatchTimer = null;
    _stopwatchElapsedSeconds.value = 0;
    setState(() {
      _stopwatchRunning = false;
      _stopwatchAccumulatedSeconds = 0;
      _stopwatchSegmentStartedAt = null;
    });
  }

  Future<void> _stopAndSaveStopwatch(_TimeAuditOrigin origin) async {
    _stopwatchTimer?.cancel();
    _stopwatchTimer = null;
    final seconds = math.max(1, _stopwatchElapsedSeconds.value);
    final category = _stopwatchCategory;
    final customTitle = _stopwatchCustomTitle.trim();
    final title = customTitle.isEmpty
        ? TimeAuditUiCopy.defaultSessionLabel(category)
        : customTitle;
    _stopwatchElapsedSeconds.value = 0;
    setState(() {
      _stopwatchRunning = false;
      _stopwatchAccumulatedSeconds = 0;
      _stopwatchSegmentStartedAt = null;
    });
    if (!origin.isCurrent(context)) return;
    final endAt = DateTime.now();
    final startAt = endAt.subtract(Duration(seconds: seconds));
    await origin.provider.add(
      TimeEntry(
        title: title,
        startAt: startAt,
        endAt: endAt,
        category: category,
        source: TimeEntrySource.manual,
        note: TimeAuditUiCopy.stopwatchRecordedNote,
      ),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(TimeAuditUiCopy.recordedSaved(title)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _renameStopwatchLabel() async {
    final controller = TextEditingController(text: _stopwatchCustomTitle);
    final result = await showControllerDialog<String>(
      context: context,
      controllers: [controller],
      builder: (dialogCtx) => AlertDialog(
        title: Text(TimeAuditUiCopy.renameDialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: TimeAuditUiCopy.renameDialogHint,
          ),
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(''),
            child: Text(TimeAuditUiCopy.clearLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(controller.text),
            child: Text(I18n.tr('action.save')),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _stopwatchCustomTitle = result.trim());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TimeAuditProvider>();
    _openInitialEntryIfNeeded(provider);
    final origin = _TimeAuditOrigin.capture(context);
    final entries = _entriesFor(provider);
    if (_view == _AuditView.timeline) {
      _scheduleHighlightScroll(entries);
    }
    final totalSeconds = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.durationSeconds,
    );
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : null,
      appBar: AppBar(
        title: Text(I18n.tr('time_audit.title')),
        actions: [
          IconButton(
            key: const ValueKey('time_audit_export_csv_btn'),
            tooltip: TimeAuditUiCopy.exportCsvTooltip,
            icon: const Icon(Icons.download_outlined),
            onPressed: entries.isEmpty
                ? null
                : () => _exportCsv(origin, entries),
          ),
          IconButton(
            tooltip: I18n.tr('time_audit.copy_report'),
            icon: const Icon(Icons.content_copy_outlined),
            onPressed: entries.isEmpty
                ? null
                : () => _copyReport(origin, entries),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'time_audit_add_fab',
        onPressed: () => _showEditor(context, origin),
        icon: const Icon(Icons.add),
        label: Text(I18n.tr('time_audit.add_manual')),
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        children: [
          _StopwatchTrackerCard(
            running: _stopwatchRunning,
            elapsedSecondsListenable: _stopwatchElapsedSeconds,
            category: _stopwatchCategory,
            customLabel: _stopwatchCustomTitle,
            onSelectCategory: (c) => setState(() => _stopwatchCategory = c),
            onRenameLabel: _renameStopwatchLabel,
            onStartOrResume: _startOrResumeStopwatch,
            onPause: _pauseStopwatch,
            onStopAndSave: () => _stopAndSaveStopwatch(origin),
            onDiscard: _resetStopwatch,
          ),
          const SizedBox(height: 8),
          _SummaryCard(
            rangeLabel: _rangeLabel(_range),
            totalSeconds: totalSeconds,
            entries: entries,
          ),
          const SizedBox(height: 8),
          _HorizontalSegmentStrip(
            child: SegmentedButton<_AuditRange>(
              segments: [
                ButtonSegment(
                  value: _AuditRange.today,
                  label: Text(I18n.tr('time_audit.segment.today')),
                ),
                ButtonSegment(
                  value: _AuditRange.week,
                  label: Text(I18n.tr('time_audit.range.week')),
                ),
                ButtonSegment(
                  value: _AuditRange.month,
                  label: Text(I18n.tr('time_audit.range.month')),
                ),
                ButtonSegment(
                  value: _AuditRange.all,
                  label: Text(I18n.tr('time_audit.range.all')),
                ),
              ],
              selected: {_range},
              onSelectionChanged: (value) =>
                  setState(() => _range = value.first),
            ),
          ),
          const SizedBox(height: 8),
          _HorizontalSegmentStrip(
            child: SegmentedButton<_AuditView>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _AuditView.timeline,
                  icon: const Icon(Icons.view_agenda_outlined),
                  label: Text(I18n.tr('time_audit.view.timeline')),
                ),
                ButtonSegment(
                  value: _AuditView.category,
                  icon: const Icon(Icons.donut_small_outlined),
                  label: Text(I18n.tr('time_audit.view.category')),
                ),
                ButtonSegment(
                  value: _AuditView.calendar,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(I18n.tr('time_audit.view.calendar')),
                ),
                ButtonSegment(
                  value: _AuditView.trend,
                  icon: const Icon(Icons.bar_chart_outlined),
                  label: Text(I18n.tr('time_audit.view.trend')),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (value) =>
                  setState(() => _view = value.first),
            ),
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            AppSurfaceCard(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
              child: Column(
                children: [
                  Icon(
                    Icons.timeline_outlined,
                    size: 42,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.32),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_rangeLabel(_range)}${I18n.tr('time_audit.empty.suffix')}',
                  ),
                ],
              ),
            )
          else
            _buildActiveView(context, origin, entries),
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

  Widget _buildActiveView(
    BuildContext context,
    _TimeAuditOrigin origin,
    List<TimeEntry> entries,
  ) {
    return switch (_view) {
      _AuditView.timeline => _TimelineView(
        rangeLabel: _rangeLabel(_range),
        entries: entries,
        highlightedEntryId: _highlightedEntryId,
        entryKeyBuilder: _keyForEntry,
        onEdit: (entry) => _showEditor(context, origin, entry: entry),
        onDelete: (entry) => _deleteEntry(origin, entry),
      ),
      _AuditView.category => _CategoryView(
        entries: entries,
        onCategoryTap: (category) {
          setState(() => _view = _AuditView.timeline);
        },
      ),
      _AuditView.calendar => _CalendarAuditView(
        entries: entries,
        onEdit: (entry) => _showEditor(context, origin, entry: entry),
      ),
      _AuditView.trend => _TrendAuditView(entries: entries),
    };
  }

  void _showEditor(
    BuildContext context,
    _TimeAuditOrigin origin, {
    TimeEntry? entry,
  }) {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && (!route.isActive || !route.isCurrent)) return;
    if (!origin.isCurrent(context)) return;
    if (entry != null &&
        !origin.provider.entries.any((e) => e.id == entry.id)) {
      return;
    }
    showAppModalSheet(
      context: context,
      builder: (_) => _TimeEntrySheet(origin: origin, entry: entry),
    );
  }

  Future<void> _deleteEntry(_TimeAuditOrigin origin, TimeEntry entry) async {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && (!route.isActive || !route.isCurrent)) return;
    if (!origin.isCurrent(context)) return;
    if (!origin.provider.entries.any((e) => e.id == entry.id)) return;
    await origin.provider.delete(entry.id);
  }

  Future<void> _exportCsv(
    _TimeAuditOrigin origin,
    List<TimeEntry> entries,
  ) async {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && (!route.isActive || !route.isCurrent)) return;
    if (!origin.isCurrent(context)) return;
    final csv = ModuleExporter.timeEntriesCsv(entries);
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final result = await WebFileDownload.saveText(
      content: csv,
      fileName: 'duoyi-time-audit-$stamp.csv',
      mimeType: 'text/csv;charset=utf-8',
    );
    if (!mounted) return;
    if (!origin.isCurrent(context)) return;
    if (result.dismissed) return;
    if (!result.saved) {
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null || !messenger.mounted) return;
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.saved
                ? TimeAuditUiCopy.csvExported(result.fileName)
                : TimeAuditUiCopy.csvCopiedFallback,
          ),
          action: result.saved
              ? SnackBarAction(
                  label: TimeAuditUiCopy.copyCsvAction,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: csv));
                  },
                )
              : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _copyReport(
    _TimeAuditOrigin origin,
    List<TimeEntry> entries,
  ) async {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && (!route.isActive || !route.isCurrent)) return;
    if (!origin.isCurrent(context)) return;
    final report = _buildReport(entries, AppDateFormat.readPattern(context));
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    if (route != null && (!route.isActive || !route.isCurrent)) return;
    if (!origin.isCurrent(context)) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null || !messenger.mounted) return;
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (_, _, _) => Text(I18n.tr('time_audit.report_copied')),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _buildReport(List<TimeEntry> entries, String? pattern) {
    final totalSeconds = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.durationSeconds,
    );
    final byCategory = <TimeEntryCategory, int>{};
    for (final entry in entries) {
      byCategory[entry.category] =
          (byCategory[entry.category] ?? 0) + entry.durationSeconds;
    }
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sorted = [...entries]..sort((a, b) => a.startAt.compareTo(b.startAt));
    final separator = _labelSeparator();
    final buffer = StringBuffer()
      ..writeln('# ${I18n.tr('time_audit.report.title')}')
      ..writeln()
      ..writeln(
        '- ${I18n.tr('time_audit.report.range')}$separator${_rangeLabel(_range)}',
      )
      ..writeln(
        '- ${I18n.tr('time_audit.report.total')}$separator${_formatDuration(totalSeconds)}',
      )
      ..writeln(
        '- ${I18n.tr('time_audit.entry_count')}$separator${entries.length}',
      )
      ..writeln()
      ..writeln('## ${I18n.tr('time_audit.report.category')}');
    for (final item in categories) {
      buffer.writeln(
        '- ${item.key.label}$separator${_formatDuration(item.value)}',
      );
    }
    buffer
      ..writeln()
      ..writeln('## ${I18n.tr('time_audit.report.details')}');
    for (final entry in sorted) {
      buffer.writeln(
        '- ${I18nDateFormat.date(entry.startAt, pattern: pattern)} ${_clock(entry.startAt)}-${_clock(entry.endAt)} '
        '${entry.title} · ${entry.category.label} · ${_formatDuration(entry.durationSeconds)}',
      );
    }
    return buffer.toString().trimRight();
  }

  List<TimeEntry> _entriesFor(TimeAuditProvider provider) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);
    return switch (_range) {
      _AuditRange.today => provider.entriesInRange(
        todayStart,
        todayStart.add(const Duration(days: 1)),
      ),
      _AuditRange.week => provider.entriesInRange(
        weekStart,
        weekStart.add(const Duration(days: 7)),
      ),
      _AuditRange.month => provider.entriesInRange(
        monthStart,
        DateTime(now.year, now.month + 1, 1),
      ),
      _AuditRange.all => provider.entries,
    };
  }

  String _rangeLabel(_AuditRange range) => switch (range) {
    _AuditRange.today => I18n.tr('time_audit.range.today'),
    _AuditRange.week => I18n.tr('time_audit.range.week'),
    _AuditRange.month => I18n.tr('time_audit.range.month'),
    _AuditRange.all => I18n.tr('time_audit.range.all'),
  };
}

class _StopwatchTrackerCard extends StatelessWidget {
  final bool running;
  final ValueListenable<int> elapsedSecondsListenable;
  final TimeEntryCategory category;
  final String customLabel;
  final ValueChanged<TimeEntryCategory> onSelectCategory;
  final VoidCallback onRenameLabel;
  final VoidCallback onStartOrResume;
  final VoidCallback onPause;
  final VoidCallback onStopAndSave;
  final VoidCallback onDiscard;

  const _StopwatchTrackerCard({
    required this.running,
    required this.elapsedSecondsListenable,
    required this.category,
    required this.customLabel,
    required this.onSelectCategory,
    required this.onRenameLabel,
    required this.onStartOrResume,
    required this.onPause,
    required this.onStopAndSave,
    required this.onDiscard,
  });

  String _formatClock(int totalSeconds) {
    final hours = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String get _startButtonLabel =>
      I18n.current == AppLocale.en ? 'Start timer' : TimeAuditUiCopy.start;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final elapsedSeconds = elapsedSecondsListenable.value;
    final statusText = running
        ? TimeAuditUiCopy.statusRunning
        : (elapsedSeconds > 0
              ? TimeAuditUiCopy.statusPaused
              : TimeAuditUiCopy.statusReady);
    final labelText = customLabel.trim().isEmpty
        ? TimeAuditUiCopy.defaultSessionLabel(category)
        : customLabel.trim();
    final accent = running ? cs.primary : cs.onSurfaceVariant;
    final compactButtonStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return AppSurfaceCard(
      key: const ValueKey('time_audit_stopwatch_card'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      border: running
          ? Border.all(color: cs.primary, width: 0.6)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 18, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  TimeAuditUiCopy.stopwatchTitle,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: running
                      ? cs.primary.withValues(alpha: 0.14)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    color: running ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  RepaintBoundary(
                    child: ValueListenableBuilder<int>(
                      valueListenable: elapsedSecondsListenable,
                      builder: (context, elapsed, _) => Text(
                        _formatClock(elapsed),
                        key: const ValueKey('time_audit_stopwatch_readout'),
                        style: TextStyle(
                          fontSize: 22,
                          color: running ? cs.primary : cs.onSurface,
                          fontWeight: FontWeight.normal,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    key: const ValueKey('time_audit_stopwatch_rename_btn'),
                    onTap: onRenameLabel,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _iconFor(category),
                            size: 14,
                            color: _colorFor(category, cs),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            labelText,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit_outlined,
                            size: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (!running)
                    FilledButton.icon(
                      key: const ValueKey('time_audit_stopwatch_start_btn'),
                      style: compactButtonStyle,
                      onPressed: onStartOrResume,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(
                        elapsedSeconds > 0
                            ? TimeAuditUiCopy.resume
                            : _startButtonLabel,
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      key: const ValueKey('time_audit_stopwatch_pause_btn'),
                      style: compactButtonStyle,
                      onPressed: onPause,
                      icon: const Icon(Icons.pause_rounded, size: 18),
                      label: Text(TimeAuditUiCopy.pause),
                    ),
                  if (running || elapsedSeconds > 0)
                    FilledButton.icon(
                      key: const ValueKey('time_audit_stopwatch_stop_btn'),
                      style: compactButtonStyle,
                      onPressed: onStopAndSave,
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: Text(TimeAuditUiCopy.stopAndSave),
                    ),
                  if (!running && elapsedSeconds > 0)
                    TextButton(
                      key: const ValueKey('time_audit_stopwatch_discard_btn'),
                      style: compactButtonStyle,
                      onPressed: onDiscard,
                      child: Text(TimeAuditUiCopy.discard),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in TimeEntryCategory.values) ...[
                  ChoiceChip(
                    key: ValueKey('time_audit_stopwatch_cat_${item.name}'),
                    avatar: Icon(
                      _iconFor(item),
                      size: 14,
                      color: _colorFor(item, cs),
                    ),
                    label: Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    selected: category == item,
                    onSelected: (_) => onSelectCategory(item),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineView extends StatelessWidget {
  final String rangeLabel;
  final List<TimeEntry> entries;
  final String? highlightedEntryId;
  final GlobalKey Function(String id)? entryKeyBuilder;
  final ValueChanged<TimeEntry> onEdit;
  final ValueChanged<TimeEntry> onDelete;

  const _TimelineView({
    required this.rangeLabel,
    required this.entries,
    this.highlightedEntryId,
    this.entryKeyBuilder,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          child: Text(
            _rangeViewTitle(rangeLabel, I18n.tr('time_audit.view.timeline')),
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          ),
        ),
        for (final entry in entries) ...[
          _TimeEntryCard(
            key: entryKeyBuilder?.call(entry.id),
            entry: entry,
            highlighted: entry.id == highlightedEntryId,
            onTap: () => onEdit(entry),
            onDelete: () => onDelete(entry),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CategoryView extends StatelessWidget {
  final List<TimeEntry> entries;
  final ValueChanged<TimeEntryCategory> onCategoryTap;

  const _CategoryView({required this.entries, required this.onCategoryTap});

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.durationSeconds,
    );
    final byCategory = <TimeEntryCategory, int>{};
    final bySource = <TimeEntrySource, int>{};
    for (final entry in entries) {
      byCategory[entry.category] =
          (byCategory[entry.category] ?? 0) + entry.durationSeconds;
      bySource[entry.source] =
          (bySource[entry.source] ?? 0) + entry.durationSeconds;
    }
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sources = bySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          child: Text(
            I18n.tr('time_audit.category_view'),
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          ),
        ),
        AppSurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              for (final item in categories)
                _CategoryBreakdownTile(
                  category: item.key,
                  seconds: item.value,
                  totalSeconds: total,
                  onTap: () => onCategoryTap(item.key),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppSurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                I18n.tr('time_audit.source_breakdown'),
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              for (final item in sources)
                _SourceBreakdownRow(
                  source: item.key,
                  seconds: item.value,
                  totalSeconds: total,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryBreakdownTile extends StatelessWidget {
  final TimeEntryCategory category;
  final int seconds;
  final int totalSeconds;
  final VoidCallback onTap;

  const _CategoryBreakdownTile({
    required this.category,
    required this.seconds,
    required this.totalSeconds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(category, Theme.of(context).colorScheme);
    final ratio = totalSeconds <= 0 ? 0.0 : seconds / totalSeconds;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconFor(category), color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(category.label)),
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(seconds),
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 7,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.12),
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

class _SourceBreakdownRow extends StatelessWidget {
  final TimeEntrySource source;
  final int seconds;
  final int totalSeconds;

  const _SourceBreakdownRow({
    required this.source,
    required this.seconds,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = totalSeconds <= 0 ? 0.0 : seconds / totalSeconds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(source.label, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(seconds),
                style: const TextStyle(
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              color: cs.primary,
              backgroundColor: cs.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarAuditView extends StatelessWidget {
  final List<TimeEntry> entries;
  final ValueChanged<TimeEntry> onEdit;

  const _CalendarAuditView({required this.entries, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final grouped = <DateTime, List<TimeEntry>>{};
    for (final entry in entries) {
      final day = DateTime(
        entry.startAt.year,
        entry.startAt.month,
        entry.startAt.day,
      );
      grouped.putIfAbsent(day, () => <TimeEntry>[]).add(entry);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          child: Text(
            I18n.tr('time_audit.calendar_view'),
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          ),
        ),
        for (final day in days) ...[
          _DayGroupCard(day: day, entries: grouped[day]!, onEdit: onEdit),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TrendAuditView extends StatelessWidget {
  final List<TimeEntry> entries;

  const _TrendAuditView({required this.entries});

  @override
  Widget build(BuildContext context) {
    final grouped = <DateTime, List<TimeEntry>>{};
    for (final entry in entries) {
      final day = DateTime(
        entry.startAt.year,
        entry.startAt.month,
        entry.startAt.day,
      );
      grouped.putIfAbsent(day, () => <TimeEntry>[]).add(entry);
    }
    final days = grouped.keys.toList()..sort();
    final totals = {
      for (final day in days)
        day: grouped[day]!.fold<int>(
          0,
          (sum, entry) => sum + entry.durationSeconds,
        ),
    };
    final maxSeconds = totals.values.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          child: Text(
            I18n.tr('time_audit.trend_view'),
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          ),
        ),
        AppSurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              for (final day in days)
                _TrendDayRow(
                  day: day,
                  entries: grouped[day]!,
                  totalSeconds: totals[day] ?? 0,
                  maxSeconds: maxSeconds,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendDayRow extends StatelessWidget {
  final DateTime day;
  final List<TimeEntry> entries;
  final int totalSeconds;
  final int maxSeconds;

  const _TrendDayRow({
    required this.day,
    required this.entries,
    required this.totalSeconds,
    required this.maxSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = maxSeconds <= 0 ? 0.0 : totalSeconds / maxSeconds;
    final topCategory = _topCategory(entries);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${day.month}/${day.day}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(totalSeconds),
                style: const TextStyle(
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 9,
              color: topCategory == null
                  ? cs.primary
                  : _colorFor(topCategory, cs),
              backgroundColor: cs.primary.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }

  TimeEntryCategory? _topCategory(List<TimeEntry> entries) {
    if (entries.isEmpty) return null;
    final totals = <TimeEntryCategory, int>{};
    for (final entry in entries) {
      totals[entry.category] =
          (totals[entry.category] ?? 0) + entry.durationSeconds;
    }
    return totals.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

class _DayGroupCard extends StatelessWidget {
  final DateTime day;
  final List<TimeEntry> entries;
  final ValueChanged<TimeEntry> onEdit;

  const _DayGroupCard({
    required this.day,
    required this.entries,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.durationSeconds,
    );
    final sorted = [...entries]..sort((a, b) => a.startAt.compareTo(b.startAt));
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  I18nDateFormat.monthDay(day),
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(_formatDuration(total)),
            ],
          ),
          const SizedBox(height: 10),
          for (final entry in sorted)
            _CompactEntryRow(entry: entry, onTap: () => onEdit(entry)),
        ],
      ),
    );
  }
}

class _CompactEntryRow extends StatelessWidget {
  final TimeEntry entry;
  final VoidCallback onTap;

  const _CompactEntryRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(entry.category, Theme.of(context).colorScheme);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 7,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      Text(
                        entry.title,
                        style: const TextStyle(fontWeight: FontWeight.normal),
                      ),
                      Text(
                        _formatDuration(entry.durationSeconds),
                        style: const TextStyle(
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_clock(entry.startAt)}-${_clock(entry.endAt)} · ${entry.category.label}',
                    style: TextStyle(
                      fontSize: 11,
                      color: appSecondaryDescriptionColor(context),
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

class _HorizontalSegmentStrip extends StatelessWidget {
  final Widget child;

  const _HorizontalSegmentStrip({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String rangeLabel;
  final int totalSeconds;
  final List<TimeEntry> entries;

  const _SummaryCard({
    required this.rangeLabel,
    required this.totalSeconds,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final byCategory = <TimeEntryCategory, int>{};
    for (final entry in entries) {
      byCategory[entry.category] =
          (byCategory[entry.category] ?? 0) + entry.durationSeconds;
    }
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final textScaler = MediaQuery.textScalerOf(context);
              final sideBySideThreshold = 90.0 + 2.0 * textScaler.scale(98.0);
              final useRow = constraints.maxWidth >= sideBySideThreshold;

              final metric1 = _MetricBlock(
                title: '$rangeLabel${I18n.tr('time_audit.investment_suffix')}',
                value: _formatDuration(totalSeconds),
                icon: Icons.timelapse_outlined,
                color: cs.primary,
              );
              final metric2 = _MetricBlock(
                title: I18n.tr('time_audit.entry_count'),
                value:
                    '${entries.length}${I18n.tr('time_audit.entry_count_suffix')}',
                icon: Icons.list_alt_outlined,
                color: DesignTokens.defaultAccent,
              );

              if (useRow) {
                return Row(
                  children: [
                    Expanded(child: metric1),
                    const SizedBox(width: 10),
                    Expanded(child: metric2),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [metric1, const SizedBox(height: 10), metric2],
              );
            },
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final entry in categories.take(4))
              _CategoryShareRow(
                category: entry.key,
                seconds: entry.value,
                totalSeconds: totalSeconds,
              ),
          ],
        ],
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricBlock({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 16,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: appSecondaryDescriptionColor(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryShareRow extends StatelessWidget {
  final TimeEntryCategory category;
  final int seconds;
  final int totalSeconds;

  const _CategoryShareRow({
    required this.category,
    required this.seconds,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(category, Theme.of(context).colorScheme);
    final ratio = totalSeconds <= 0 ? 0.0 : seconds / totalSeconds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category.label,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(seconds),
                style: const TextStyle(
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeEntryCard extends StatelessWidget {
  final TimeEntry entry;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TimeEntryCard({
    super.key,
    required this.entry,
    this.highlighted = false,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(entry.category, Theme.of(context).colorScheme);
    return AppSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      border: highlighted
          ? Border.all(color: Theme.of(context).colorScheme.primary, width: 0.6)
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconFor(entry.category), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDateTime(entry.startAt)} - ${_formatDateTime(entry.endAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: appSecondaryDescriptionColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Chip(text: entry.category.label),
                    _Chip(text: entry.source.label),
                    _Chip(text: _formatDuration(entry.durationSeconds)),
                    if (entry.note.isNotEmpty) _Chip(text: entry.note),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: I18n.tr('action.delete'),
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _TimeEntrySheet extends StatefulWidget {
  final TimeEntry? entry;
  final _TimeAuditOrigin origin;

  const _TimeEntrySheet({this.entry, required this.origin});

  @override
  State<_TimeEntrySheet> createState() => _TimeEntrySheetState();
}

class _TimeEntrySheetState extends State<_TimeEntrySheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _minutesCtrl;
  late TimeEntryCategory _category;
  late DateTime _startAt;
  late DateTime _endAt;
  late final String _draftId;
  late final DateTime _draftCreatedAt;
  late final bool _isExistingEntry;
  ModalRoute<dynamic>? _owningRoute;
  bool _saving = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
    final entry = widget.entry;
    _titleCtrl = TextEditingController(
      text: entry?.title ?? I18n.tr('time_audit.default_title'),
    );
    _noteCtrl = TextEditingController(text: entry?.note ?? '');
    _minutesCtrl = TextEditingController(
      text: entry == null
          ? '25'
          : (entry.durationSeconds ~/ 60).clamp(1, 1440).toString(),
    );
    _category = entry?.category ?? TimeEntryCategory.focus;
    _startAt = entry?.startAt ?? DateTime.now();
    _endAt = entry?.endAt ?? DateTime.now().add(const Duration(minutes: 25));
    if (entry != null) {
      _isExistingEntry = true;
      _draftId = entry.id;
      _draftCreatedAt = entry.createdAt;
    } else {
      _isExistingEntry = false;
      final temp = TimeEntry(title: '', startAt: _startAt, endAt: _endAt);
      _draftId = temp.id;
      _draftCreatedAt = temp.createdAt;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _owningRoute ??= ModalRoute.of(context);
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  bool _canAct({bool checkRoute = true}) {
    if (!mounted) return false;
    final route = _owningRoute ?? ModalRoute.of(context);
    if (route != null) {
      if (!route.isActive) return false;
      if (checkRoute && !route.isCurrent) return false;
    }
    return widget.origin.isCurrent(context, checkRoute: false);
  }

  void _dismissOwningSheet() {
    final route = _owningRoute ?? ModalRoute.of(context);
    if (route != null && route.isActive) {
      final nav = route.navigator ?? Navigator.maybeOf(context);
      if (nav != null) {
        if (route.isCurrent) {
          nav.pop();
        } else {
          nav.removeRoute(route);
        }
      }
    }
  }

  void _cancel() {
    if (_saving || !_canAct()) return;
    _dismissOwningSheet();
  }

  void _showSaveError() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null || !messenger.mounted) return;
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (_, _, _) => Text(
              '${I18n.tr('profile.save_failed')}, ${I18n.tr('action.retry')}',
            ),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AppModalSheet(
      title: widget.entry == null
          ? I18n.tr('time_audit.sheet.add_title')
          : I18n.tr('time_audit.sheet.edit_title'),
      actions: [
        TextButton(
          onPressed: _saving ? null : _cancel,
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(I18n.tr('action.save')),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              labelText: I18n.tr('time_audit.field.title'),
              prefixIcon: const Icon(Icons.title, size: 20),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          AppDropdownField<TimeEntryCategory>(
            initialValue: _category,
            labelText: I18n.tr('time_audit.field.category'),
            prefixIcon: const Icon(Icons.label_outline, size: 20),
            items: [
              for (final c in TimeEntryCategory.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _category = v);
            },
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          LayoutBuilder(
            builder: (context, constraints) {
              final startTile = _TimeEndpointTile(
                icon: Icons.play_arrow,
                title: I18n.tr('time_audit.field.start'),
                subtitle: _formatDateTime(_startAt),
                onTap: (_saving || _picking) ? null : _pickStart,
              );
              final endTile = _TimeEndpointTile(
                icon: Icons.stop,
                title: I18n.tr('time_audit.field.end'),
                subtitle: _formatDateTime(_endAt),
                onTap: (_saving || _picking) ? null : _pickEnd,
              );
              if (constraints.maxWidth < 360) {
                return Column(
                  children: [
                    startTile,
                    const SizedBox(height: DesignTokens.spaceXs),
                    endTile,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: startTile),
                  const SizedBox(width: DesignTokens.spaceSm),
                  Expanded(child: endTile),
                ],
              );
            },
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          TextField(
            controller: _minutesCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: I18n.tr('time_audit.field.minutes'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: I18n.tr('time_audit.field.note'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStart() async {
    if (_saving || _picking || !_canAct()) return;
    _picking = true;
    try {
      final date = await AppDatePicker.pickSolar(
        context,
        initialDate: _startAt,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        titleKey: 'time_audit.picker.start_date',
      );
      if (date == null || !_canAct()) return;
      if (!mounted) return;
      final time = await AppTimePicker.show(
        context,
        initialTime: TimeOfDay.fromDateTime(_startAt),
        titleKey: 'time_audit.picker.start_time',
        minuteStep: 5,
      );
      if (time == null || !_canAct()) return;
      setState(() {
        _startAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
        final minutes = int.tryParse(_minutesCtrl.text.trim()) ?? 25;
        _endAt = _startAt.add(Duration(minutes: minutes));
      });
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      } else {
        _picking = false;
      }
    }
  }

  Future<void> _pickEnd() async {
    if (_saving || _picking || !_canAct()) return;
    _picking = true;
    try {
      final date = await AppDatePicker.pickSolar(
        context,
        initialDate: _endAt,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        titleKey: 'time_audit.picker.end_date',
      );
      if (date == null || !_canAct()) return;
      if (!mounted) return;
      final time = await AppTimePicker.show(
        context,
        initialTime: TimeOfDay.fromDateTime(_endAt),
        titleKey: 'time_audit.picker.end_time',
        minuteStep: 5,
      );
      if (time == null || !_canAct()) return;
      setState(() {
        _endAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      } else {
        _picking = false;
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _picking || !_canAct()) return;
    final origin = widget.origin;

    if (_isExistingEntry) {
      final exists = origin.provider.entries.any((e) => e.id == _draftId);
      if (!exists) {
        if (mounted && _canAct(checkRoute: true)) {
          _showSaveError();
        }
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final minutes = int.tryParse(_minutesCtrl.text.trim()) ?? 0;
      final endAt = _endAt.isAfter(_startAt)
          ? _endAt
          : _startAt.add(Duration(minutes: minutes <= 0 ? 1 : minutes));
      final entry = TimeEntry(
        id: _draftId,
        title: _titleCtrl.text.trim().isEmpty
            ? I18n.tr('time_audit.default_title')
            : _titleCtrl.text.trim(),
        startAt: _startAt,
        endAt: endAt,
        category: _category,
        source: widget.entry?.source ?? TimeEntrySource.manual,
        sourceId: widget.entry?.sourceId,
        dedupeKey: widget.entry?.dedupeKey,
        note: _noteCtrl.text.trim(),
        createdAt: _draftCreatedAt,
      );

      if (_isExistingEntry ||
          origin.provider.entries.any((e) => e.id == _draftId)) {
        await origin.provider.update(entry);
      } else {
        await origin.provider.add(entry);
      }

      if (!mounted) return;
      if (!origin.isCurrent(context, checkRoute: false)) {
        return;
      }

      _dismissOwningSheet();
    } catch (_) {
      if (mounted && _canAct(checkRoute: true)) {
        _showSaveError();
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _TimeEndpointTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _TimeEndpointTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}

String _formatDateTime(DateTime d) => I18nDateFormat.shortDateTime(d);

String _clock(DateTime d) => I18nDateFormat.time(d);

String _formatDuration(int seconds) {
  if (seconds >= 3600) {
    return '${(seconds / 3600).toStringAsFixed(seconds % 3600 == 0 ? 0 : 1)} ${I18n.tr('unit.hour')}';
  }
  return '${(seconds / 60).toStringAsFixed(seconds % 60 == 0 ? 0 : 1)} ${I18n.tr('unit.minute')}';
}

String _rangeViewTitle(String rangeLabel, String viewLabel) {
  return switch (I18n.current) {
    AppLocale.en => '$rangeLabel $viewLabel',
    AppLocale.zh => '$rangeLabel$viewLabel',
  };
}

String _labelSeparator() {
  return switch (I18n.current) {
    AppLocale.en => ': ',
    AppLocale.zh => '：',
  };
}

Color _colorFor(TimeEntryCategory category, ColorScheme cs) =>
    switch (category) {
      TimeEntryCategory.focus => DesignTokens.defaultError,
      TimeEntryCategory.todo => cs.primary,
      TimeEntryCategory.habit => DesignTokens.defaultSuccess,
      TimeEntryCategory.goal => cs.tertiary,
      TimeEntryCategory.study => DesignTokens.defaultAccent,
      TimeEntryCategory.work => DesignTokens.defaultWarning,
      TimeEntryCategory.life => cs.secondary,
      TimeEntryCategory.other => cs.onSurfaceVariant,
    };

IconData _iconFor(TimeEntryCategory category) => switch (category) {
  TimeEntryCategory.focus => Icons.timer_outlined,
  TimeEntryCategory.todo => Icons.check_circle_outline,
  TimeEntryCategory.habit => Icons.repeat,
  TimeEntryCategory.goal => Icons.flag_outlined,
  TimeEntryCategory.study => Icons.menu_book_outlined,
  TimeEntryCategory.work => Icons.work_outline,
  TimeEntryCategory.life => Icons.favorite_outline,
  TimeEntryCategory.other => Icons.more_horiz,
};
