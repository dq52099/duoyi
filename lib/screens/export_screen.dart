import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/account_preference_writes.dart';
import '../core/design_tokens.dart';
import '../core/export_ui_copy.dart';
import '../core/i18n.dart';
import '../models/calendar_event.dart';
import '../providers/auth_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/api_client.dart';
import '../services/settings_action_origin.dart';
import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;
import '../providers/anniversary_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/todo_provider.dart';
import '../services/calendar_sync_service.dart';
import '../services/ics_exporter.dart';
import '../services/web_file_download.dart';
import '../widgets/surface_components.dart';

/// iCalendar 导出：生成 .ics 文本供复制或订阅。
class ExportScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

typedef _ExportAccount = ({
  AuthProvider auth,
  ApiClient client,
  int session,
  int generation,
  String? userId,
  String? token,
  bool changing,
  bool blocked,
});

class _ExportSources {
  const _ExportSources(this.providers, this.data);
  final List<ChangeNotifier> providers;
  final String data;

  bool matches(_ExportSources? other) =>
      other != null &&
      listEquals(providers, other.providers) &&
      data == other.data;
}

class _ExportScreenState extends State<ExportScreen> {
  bool _includeAnniversaries = true;
  bool _includeCalendar = true;
  String? _ics;
  bool _pushingCalDav = false;

  void _rebuildCalendarIndex() {
    final ann = context.read<AnniversaryProvider>();
    final cal = context.read<CalendarProvider>();

    // 先刷新一次日历索引
    cal.rebuild(
      context.read<TodoProvider>().todos,
      context.read<HabitProvider>().habits,
      context.read<PomodoroProvider>().sessions,
      Theme.of(context).colorScheme,
      anniversaries: ann.items,
      courses: context.read<CourseProvider>().courses,
      courseSettings: context.read<CourseProvider>().settings,
      diaries: context.read<DiaryProvider>().entries,
      countdowns: context.read<CountdownProvider>().items,
      goals: context.read<GoalProvider>().goals,
    );
  }

  _ExportAccount? _account;
  _ExportSources? _sources;
  int _revision = 0;
  int _pushSerial = 0;
  bool _copying = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountChanged,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = _captureAccount(context.watch<AuthProvider>());
    final sources = _captureSources(watch: true);
    if (account != _account || !sources.matches(_sources)) {
      _invalidate();
      _account = account;
      _sources = sources;
    }
  }

  @override
  void dispose() {
    _revision++;
    _pushSerial++;
    I18n.localeListenable.removeListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountChanged,
    );
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _onAccountChanged() {
    if (!mounted) return;
    setState(() {
      _invalidate();
      _account = _captureAccount(context.read<AuthProvider>());
    });
  }

  _ExportAccount _captureAccount(AuthProvider auth) => (
    auth: auth,
    client: auth.client,
    session: auth.sessionGeneration,
    generation: AccountLocalDataCleaner.accountDataGeneration,
    userId: auth.state.userId,
    token: auth.state.token,
    changing: auth.isAccountTransitionInProgress,
    blocked: auth.isLocalAccountDataBlocked,
  );

  // Compare actual data as well as provider identity. This also rejects retained
  // callbacks before a provider notification has rebuilt this page.
  _ExportSources _captureSources({bool watch = false}) {
    T source<T>() => watch ? context.watch<T>() : context.read<T>();
    final ann = source<AnniversaryProvider>();
    final cal = source<CalendarProvider>();
    final todo = source<TodoProvider>();
    final habit = source<HabitProvider>();
    final focus = source<PomodoroProvider>();
    final course = source<CourseProvider>();
    final diary = source<DiaryProvider>();
    final countdown = source<CountdownProvider>();
    final goal = source<GoalProvider>();
    return _ExportSources(
      [ann, cal, todo, habit, focus, course, diary, countdown, goal],
      jsonEncode([
        ann.items.map((v) => v.toJson()).toList(),
        cal.sourceRevision,
        todo.todos.map((v) => v.toJson()).toList(),
        habit.habits.map((v) => v.toJson()).toList(),
        focus.sessions.map((v) => v.toJson()).toList(),
        course.courses.map((v) => v.toJson()).toList(),
        course.settings.toJson(),
        diary.entries.map((v) => v.toJson()).toList(),
        countdown.items.map((v) => v.toJson()).toList(),
        goal.goals.map((v) => v.toJson()).toList(),
      ]),
    );
  }

  void _invalidate() {
    _revision++;
    _ics = null;
    _copying = false;
    _downloading = false;
  }

  bool _mayAct(_ExportAccount account, SettingsActionOrigin origin) =>
      mounted &&
      account == _account &&
      account == _captureAccount(context.read<AuthProvider>()) &&
      !account.changing &&
      !account.blocked &&
      !AccountPreferenceWrites.isBoundaryActive &&
      origin.isCurrent();

  bool _mayExport(
    _ExportAccount account,
    SettingsActionOrigin origin,
    int revision,
    _ExportSources sources,
  ) =>
      _mayAct(account, origin) &&
      revision == _revision &&
      sources.matches(_captureSources());

  void _changeRange(bool value, {required bool anniversaries}) {
    if ((anniversaries ? _includeAnniversaries : _includeCalendar) == value) {
      return;
    }
    setState(() {
      if (anniversaries) {
        _includeAnniversaries = value;
      } else {
        _includeCalendar = value;
      }
      _invalidate();
    });
  }

  void _generate(
    _ExportAccount account,
    SettingsActionOrigin origin,
    int revision,
    _ExportSources sources,
  ) {
    if (!_mayExport(account, origin, revision, sources) ||
        (!_includeAnniversaries && !_includeCalendar)) {
      return;
    }
    _rebuildCalendarIndex();
    final items = context.read<AnniversaryProvider>().items;
    final ids = items.map((a) => a.id).toSet();
    final events = context.read<CalendarProvider>().events.where(
      (event) =>
          !(event.type == CalendarEventType.anniversary &&
              event.sourceId != null &&
              ids.contains(event.sourceId) &&
              event.id == 'anniversary_${event.sourceId}' &&
              event.displayMetadata is AnniversaryDisplayMetadata),
    );
    final text = IcsExporter.combine(
      anniversaries: _includeAnniversaries ? items : const [],
      events: _includeCalendar ? events : const [],
      calendarName: _includeCalendar
          ? ExportUiCopy.current().eventsCalendarName
          : ExportUiCopy.current().anniversariesCalendarName,
    );
    setState(() {
      _invalidate();
      _sources = _captureSources();
      _ics = text;
    });
  }

  Future<void> _pushCalDav(
    _ExportAccount account,
    SettingsActionOrigin origin,
    CalendarSyncProvider sync,
    CalDavWriteTarget target,
    int targetRevision,
  ) async {
    bool current() =>
        _mayAct(account, origin) &&
        identical(sync, context.read<CalendarSyncProvider>()) &&
        identical(target, sync.writeTarget) &&
        targetRevision == sync.writeTargetRevision &&
        !sync.isUpdatingWriteTarget;
    if (!current() || _pushingCalDav || !target.isConfigured) return;
    bool mayReport() =>
        _mayAct(account, origin) &&
        identical(sync, context.read<CalendarSyncProvider>()) &&
        sync.writeTargetRevision == targetRevision;
    final serial = ++_pushSerial;
    setState(() => _pushingCalDav = true);
    try {
      _rebuildCalendarIndex();
      // CalDAV always receives the full calendar. Its stale UID deletion
      // contract must never depend on the independent ICS range switches.
      final events = List<CalendarEvent>.of(
        context.read<CalendarProvider>().events,
      );
      final count = await sync.pushEventsToCalDav(events, isCurrent: current);
      // A successful push updates the target's timestamp, so the service owns
      // target validation; the UI checks the invoking account and route here.
      if (!mayReport() || serial != _pushSerial) return;
      _showFeedback(
        _ExportFeedbackKind.pushed,
        count: count,
        conflicts: sync.lastCalDavConflicts.length,
      );
    } on AccountPreferenceWriteCanceled {
      // Work already sent may finish remotely; no further work or stale UI.
    } catch (_) {
      if (mayReport() && serial == _pushSerial) {
        _showFeedback(_ExportFeedbackKind.pushFailed);
      }
    } finally {
      if (mounted && serial == _pushSerial) {
        setState(() => _pushingCalDav = false);
      }
    }
  }

  Future<void> _copy(
    _ExportAccount account,
    SettingsActionOrigin origin,
    int revision,
    _ExportSources sources,
    String text,
  ) async {
    bool current() =>
        _mayExport(account, origin, revision, sources) && _ics == text;
    if (!current() || _copying) return;
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (current()) _showFeedback(_ExportFeedbackKind.copied);
    } catch (_) {
      if (current()) _showFeedback(_ExportFeedbackKind.copyFailed);
    } finally {
      if (mounted && revision == _revision) setState(() => _copying = false);
    }
  }

  Future<void> _downloadIcs(
    _ExportAccount account,
    SettingsActionOrigin origin,
    int revision,
    _ExportSources sources,
    String text,
  ) async {
    bool current() =>
        _mayExport(account, origin, revision, sources) && _ics == text;
    if (!current() || _downloading) return;
    setState(() => _downloading = true);
    try {
      final now = DateTime.now();
      final dateTag =
          '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final result = await WebFileDownload.saveText(
        content: text,
        fileName: 'duoyi_calendar_$dateTag.ics',
        mimeType: 'text/calendar;charset=utf-8',
        shareSubject: 'Duoyi Calendar (.ics)',
        canProceed: current,
      );
      if (current() && result.saved) {
        _showFeedback(_ExportFeedbackKind.downloaded);
      }
    } catch (_) {
      if (current()) _showFeedback(_ExportFeedbackKind.downloadFailed);
    } finally {
      if (mounted && revision == _revision) setState(() => _downloading = false);
    }
  }

  void _showFeedback(
    _ExportFeedbackKind kind, {
    int count = 0,
    int conflicts = 0,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _ExportFeedback(kind, count: count, conflicts: conflicts),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = _account!;
    final origin = SettingsActionOrigin(context);
    final revision = _revision;
    final sources = _sources!;
    final copy = ExportUiCopy.current();
    final text = _ics;
    final ready = !account.changing && !account.blocked;
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final calendarSync = context.watch<CalendarSyncProvider>();
    final target = calendarSync.writeTarget;
    final targetRevision = calendarSync.writeTargetRevision;
    final canPushCalDav =
        ready &&
        !calendarSync.isUpdatingWriteTarget &&
        target?.isConfigured == true;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final cardFill = surfaceStyle?.cardFillColor ?? cs.surface;
    final cardBackground = Color.alphaBlend(cardFill, routeBackground);
    final copyForeground = appReadableForeground(
      cardBackground,
      isLiquidGlass ? cs.onSurface : cs.primary,
    );

    final titleStyle = appSecondaryRouteTitleTextStyle(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final appBarTheme = Theme.of(context).appBarTheme;
    final titleSpacing =
        appBarTheme.titleSpacing ?? NavigationToolbar.kMiddleSpacing;
    final hasLeading =
        ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final leadingWidth =
        hasLeading ? (appBarTheme.leadingWidth ?? kToolbarHeight) : 0.0;
    const actionsWidth = 0.0;
    final availableTitleWidth = math.max(
      0.0,
      MediaQuery.sizeOf(context).width -
          leadingWidth -
          actionsWidth -
          (titleSpacing * 2.0),
    );
    final titlePainter = TextPainter(
      text: TextSpan(text: I18n.tr('export.title'), style: titleStyle),
      textDirection: Directionality.of(context),
      textScaler: textScaler.clamp(maxScaleFactor: 1.34),
    )..layout(maxWidth: availableTitleWidth);
    final titleLineCount = titlePainter.computeLineMetrics().length;
    final titleHeight = titlePainter.height;
    titlePainter.dispose();

    final baseToolbarHeight = appBarTheme.toolbarHeight ?? kToolbarHeight;
    final effectiveToolbarHeight = titleLineCount > 1
        ? math.max(baseToolbarHeight, titleHeight + 16.0)
        : baseToolbarHeight;

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(
          I18n.tr('export.title'),
          softWrap: true,
          overflow: TextOverflow.visible,
        ),
        toolbarHeight: effectiveToolbarHeight,
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: ListView(
          key: const PageStorageKey('export_list'),
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
                      Icons.event_note_outlined,
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
                          I18n.tr('export.hero.title'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.normal,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          I18n.tr('export.hero.subtitle'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: appSecondaryDescriptionColor(
                                  context,
                                  isHero: true,
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppSettingsSection(
              title: I18n.tr('export.range.title'),
              subtitle: I18n.tr('export.range.subtitle'),
              children: [
                AppSwitchTile(
                  icon: Icons.cake_outlined,
                  color: DesignTokens.defaultAccent,
                  title: I18n.tr('export.include_anniversaries'),
                  subtitle: copy.anniversaryRangeHint,
                  value: _includeAnniversaries,
                  onChanged: ready
                      ? (v) {
                          if (_mayExport(account, origin, revision, sources)) {
                            _changeRange(v, anniversaries: true);
                          }
                        }
                      : null,
                ),
                AppSwitchTile(
                  icon: Icons.calendar_month_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  title: I18n.tr('export.include_calendar'),
                  subtitle: I18n.tr('export.include_calendar.subtitle'),
                  value: _includeCalendar,
                  onChanged: ready
                      ? (v) {
                          if (_mayExport(account, origin, revision, sources)) {
                            _changeRange(v, anniversaries: false);
                          }
                        }
                      : null,
                ),
                if (!ready || (!_includeAnniversaries && !_includeCalendar))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      ready ? copy.chooseRange : copy.accountChanging,
                    ),
                  ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        visualDensity: VisualDensity.standard,
                      ),
                      onPressed: canPushCalDav && !_pushingCalDav
                          ? () => _pushCalDav(
                              account,
                              origin,
                              calendarSync,
                              target!,
                              targetRevision,
                            )
                          : null,
                      icon: _pushingCalDav
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(I18n.tr('export.push_caldav')),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        visualDensity: VisualDensity.standard,
                      ),
                      key: const ValueKey('export_generate'),
                      onPressed:
                          ready && (_includeAnniversaries || _includeCalendar)
                          ? () => _generate(account, origin, revision, sources)
                          : null,
                      icon: const Icon(Icons.file_download_outlined),
                      label: Text(I18n.tr('export.generate_ics')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  copy.calDavScope,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (_ics != null) ...[
              const SizedBox(height: 12),
              AppSurfaceCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      I18n.tr('export.content.title'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
                          style: TextButton.styleFrom(
                            foregroundColor: copyForeground,
                            minimumSize: const Size(44, 44),
                            visualDensity: VisualDensity.standard,
                          ),
                          key: const ValueKey('export_copy'),
                          onPressed: _copying
                              ? null
                              : () => _copy(
                                  account,
                                  origin,
                                  revision,
                                  sources,
                                  text!,
                                ),
                          icon: const Icon(Icons.copy, size: 14),
                          label: Text(I18n.tr('export.copy')),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: copyForeground,
                            minimumSize: const Size(44, 44),
                            visualDensity: VisualDensity.standard,
                          ),
                          key: const ValueKey('export_download'),
                          onPressed: _downloading
                              ? null
                              : () => _downloadIcs(
                                  account,
                                  origin,
                                  revision,
                                  sources,
                                  text!,
                                ),
                          icon: const Icon(Icons.download_outlined, size: 14),
                          label: Text(
                            I18n.current == AppLocale.en
                                ? 'Download .ics'
                                : '下载 .ics 文件',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      copy.snapshotHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 220,
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _ics!,
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
  }
}

enum _ExportFeedbackKind {
  copied,
  copyFailed,
  downloaded,
  downloadFailed,
  pushed,
  pushFailed,
}

class _ExportFeedback extends StatelessWidget {
  const _ExportFeedback(this.kind, {this.count = 0, this.conflicts = 0});
  final _ExportFeedbackKind kind;
  final int count;
  final int conflicts;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, _, _) {
      final copy = ExportUiCopy.current();
      final isEn = I18n.current == AppLocale.en;
      return Text(switch (kind) {
        _ExportFeedbackKind.copied => I18n.tr('export.copy.done'),
        _ExportFeedbackKind.copyFailed => copy.copyFailed,
        _ExportFeedbackKind.downloaded =>
          isEn ? 'Downloaded .ics calendar file' : '已导出 .ics 日历文件',
        _ExportFeedbackKind.downloadFailed =>
          isEn ? 'Failed to export .ics file. Please try again.' : '导出 .ics 文件失败，请重试',
        _ExportFeedbackKind.pushFailed => copy.pushFailed,
        _ExportFeedbackKind.pushed =>
          conflicts == 0
              ? '${I18n.tr('export.caldav.success.prefix')}$count${I18n.tr('export.caldav.success.suffix')}'
              : '${I18n.tr('export.caldav.conflict.prefix')}$count${I18n.tr('export.caldav.conflict.middle')}$conflicts${I18n.tr('export.caldav.conflict.suffix')}',
      });
    },
  );
}
