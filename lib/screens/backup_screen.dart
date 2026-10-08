import 'package:flutter/material.dart';
import '../core/data_settings_ui_copy.dart';
import '../core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:provider/provider.dart';
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
import '../services/webdav_backup_service.dart';
import '../widgets/surface_components.dart';
import '../widgets/controller_dialog.dart';

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

class BackupScreen extends StatefulWidget {
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

  @override
  void initState() {
    super.initState();
    _loadWebDavConfig();
  }

  Future<void> _loadWebDavConfig() async {
    final config = await WebDavBackupService.loadConfig();
    if (!mounted) return;
    setState(() => _webDavConfig = config);
  }

  Future<void> _exportAll() async {
    setState(() => _busy = true);
    try {
      final text = await BackupService.exportAll();
      if (!mounted) return;
      setState(() {
        _exported = text;
        _currentExportKind = _ExportKind.fullJson;
        _exportedTitle = DataSettingsUiCopy.fullBackupJsonTitle;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatExportError(e))),
      );
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

  Future<void> _copy() async {
    if (_exported == null) return;
    await Clipboard.setData(ClipboardData(text: _exported!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(DataSettingsUiCopy.copiedToClipboard)),
    );
  }

  Future<void> _import({bool merge = false}) async {
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
    if (raw == null || raw.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final count = await BackupService.importAll(
        raw,
        merge: merge,
        // 覆盖=还原到备份快照：备份中不存在的本机数据一并删除，弹窗已警告。
        // 服务层 `clearMissing && !merge` 守卫保证 merge 合并入口不受影响。
        clearMissing: true,
      );
      if (!mounted) return;
      await _reloadAll();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.importSuccess(merge, count))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatImportError(e))),
      );
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
      if (ok != true) return;
      if (!mounted) return;
    }
    setState(() => _busy = true);
    try {
      final raw = await _pickImportTextFile();
      if (raw == null || raw.trim().isEmpty) {
        if (!mounted) return;
        setState(() => _busy = false);
        return;
      }
      final count = await BackupService.importAll(
        raw,
        merge: merge,
        // 覆盖=还原到备份快照：备份中不存在的本机数据一并删除，弹窗已警告。
        // 服务层 `clearMissing && !merge` 守卫保证 merge 合并入口不受影响。
        clearMissing: true,
      );
      if (!mounted) return;
      await _reloadAll();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(DataSettingsUiCopy.importFileSuccess(merge, count)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatFileImportError(e))),
      );
    }
  }

  Future<void> _importTasksFromOtherApps() async {
    final draft = await _askCompetitorImportText(tasksOnly: true);
    if (draft == null) return;
    await _previewAndImportCompetitorData(draft, tasksOnly: true);
  }

  Future<void> _importProductivityDataFromOtherApps() async {
    final draft = await _askCompetitorImportText(tasksOnly: false);
    if (draft == null) return;
    await _previewAndImportCompetitorData(draft, tasksOnly: false);
  }

  Future<void> _importProductivityDataFile() async {
    try {
      final raw = await _pickImportTextFile();
      if (raw == null || raw.trim().isEmpty) return;
      final config = await _selectCompetitorImportSource();
      if (config == null) return;
      await _previewAndImportCompetitorData(
        _CompetitorImportDraft(
          raw: raw,
          source: config.source,
          fieldMapping: config.fieldMapping,
        ),
        tasksOnly: false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatFileMigrationError(e))),
      );
    }
  }

  Future<_CompetitorImportDraft?> _askCompetitorImportText({
    required bool tasksOnly,
  }) async {
    final ctrl = TextEditingController();
    var source = _CompetitorImportSource.zhijianTime;
    var fieldMapping = const CompetitorFieldMapping();
    final draft = await showControllerDialog<_CompetitorImportDraft>(
      context: context,
      controllers: [ctrl],
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
                        final updated = await _editCompetitorFieldMapping(
                          fieldMapping,
                        );
                        if (updated == null) return;
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
                onPressed: () => Navigator.pop(ctx),
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: () {
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

  Future<_CompetitorImportConfig?> _selectCompetitorImportSource() {
    var source = _CompetitorImportSource.zhijianTime;
    var fieldMapping = const CompetitorFieldMapping();
    return showDialog<_CompetitorImportConfig>(
      context: context,
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
                      final updated = await _editCompetitorFieldMapping(
                        fieldMapping,
                      );
                      if (updated == null) return;
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
                onPressed: () => Navigator.pop(ctx),
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  ctx,
                  _CompetitorImportConfig(
                    source: source,
                    fieldMapping: fieldMapping,
                  ),
                ),
                child: Text(
                  DataSettingsUiCopy.importCompetitorFileSourceAction,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _previewAndImportCompetitorData(
    _CompetitorImportDraft draft, {
    required bool tasksOnly,
  }) async {
    final parsed = const CompetitorTaskImporter().parse(
      draft.raw,
      fieldMapping: draft.fieldMapping,
    );
    final recognized = tasksOnly ? parsed.todos.length : parsed.totalImported;
    if (recognized == 0) {
      if (!mounted) return;
      final separator = DataSettingsUiCopy.isEn ? '; ' : '；';
      final warning = parsed.warnings.isEmpty
          ? ''
          : (DataSettingsUiCopy.isEn
                ? ': ${parsed.warnings.take(2).join(separator)}'
                : '：${parsed.warnings.take(2).join(separator)}');
      ScaffoldMessenger.of(context).showSnackBar(
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
    );
    if (confirmed != true || !mounted) return;

    final todoProvider = context.read<TodoProvider>();
    final habitProvider = context.read<HabitProvider>();
    final noteProvider = context.read<NoteProvider>();
    final calendarProvider = context.read<CalendarProvider>();
    final anniversaryProvider = context.read<AnniversaryProvider>();
    final countdownProvider = context.read<CountdownProvider>();
    final timeAuditProvider = context.read<TimeAuditProvider>();
    setState(() => _busy = true);
    try {
      final rollbackSnapshot = await BackupService.exportAll();
      if (!mounted) return;
      final todoSummary = await todoProvider.importTodos(parsed.todos);
      final habitSummary = tasksOnly
          ? const HabitImportSummary(inserted: 0, skippedDuplicates: 0)
          : await habitProvider.importHabits(parsed.habits);
      final noteSummary = tasksOnly
          ? const NoteImportSummary(inserted: 0, skippedDuplicates: 0)
          : await noteProvider.importNotes(parsed.notes);
      final eventSummary = tasksOnly
          ? const CalendarEventImportSummary(inserted: 0, skippedDuplicates: 0)
          : await calendarProvider.importLocalEvents(parsed.calendarEvents);
      final anniversarySummary = tasksOnly
          ? const AnniversaryImportSummary(inserted: 0, skippedDuplicates: 0)
          : await anniversaryProvider.importAnniversaries(parsed.anniversaries);
      final countdownSummary = tasksOnly
          ? const CountdownImportSummary(inserted: 0, skippedDuplicates: 0)
          : await countdownProvider.importCountdowns(parsed.countdowns);
      final timeEntrySummary = tasksOnly
          ? const TimeEntryImportSummary(inserted: 0, skippedDuplicates: 0)
          : await timeAuditProvider.importTimeEntries(parsed.timeEntries);
      if (!mounted) return;
      setState(() => _busy = false);
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
      final undo = await _showCompetitorImportResult(
        draft: draft,
        parsed: parsed,
        summary: summary,
        tasksOnly: tasksOnly,
        rollbackSnapshot: rollbackSnapshot,
      );
      if (!mounted) return;
      if (undo == true) {
        await _rollbackCompetitorImport(rollbackSnapshot);
      } else {
        final reminderIssueSuffix = summary.hasReminderSyncIssues
            ? DataSettingsUiCopy.partialRemindersSuffix
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              DataSettingsUiCopy.importSuccessBanner(
                _competitorSourceLabel(draft.source),
                summary.inserted,
                summary.skipped,
                reminderIssueSuffix,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatDataMigrationError(e))),
      );
    }
  }

  Future<bool> _confirmCompetitorImportPreview({
    required _CompetitorImportDraft draft,
    required CompetitorTaskImportResult parsed,
    required bool tasksOnly,
  }) async {
    var confirmed = false;
    final otherModuleCount = parsed.totalImported - parsed.todos.length;
    return await showDialog<bool>(
          context: context,
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
                            DataSettingsUiCopy.tasksOnlyNotice(
                              otherModuleCount,
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
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
                            setDialogState(() => confirmed = value == true);
                          },
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
                      onPressed: confirmed
                          ? () => Navigator.pop(ctx, true)
                          : null,
                      child: Text(DataSettingsUiCopy.confirmImport),
                    ),
                  ],
                );
              },
            ),
          ),
        ) ??
        false;
  }

  Future<bool> _showCompetitorImportResult({
    required _CompetitorImportDraft draft,
    required CompetitorTaskImportResult parsed,
    required _CompetitorImportApplySummary summary,
    required bool tasksOnly,
    required String rollbackSnapshot,
  }) async {
    assert(rollbackSnapshot.isNotEmpty);
    final separator = DataSettingsUiCopy.isEn ? '; ' : '；';
    return await showDialog<bool>(
          context: context,
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
                  if (tasksOnly &&
                      parsed.totalImported > parsed.todos.length) ...[
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
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(DataSettingsUiCopy.undoImport),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(DataSettingsUiCopy.gotIt),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _rollbackCompetitorImport(String rollbackSnapshot) async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await BackupService.importAll(
        rollbackSnapshot,
        merge: false,
        clearMissing: true,
      );
      if (!mounted) return;
      await _reloadAll();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.undoImportSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatRollbackError(e))),
      );
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
    CompetitorFieldMapping initial,
  ) async {
    final controllers = <String, TextEditingController>{
      for (final target in _competitorFieldMappingTargets)
        target.$1: TextEditingController(text: initial.sourceFor(target.$1)),
    };
    return await showControllerDialog<CompetitorFieldMapping>(
      context: context,
      controllers: [...controllers.values],
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
                for (final controller in controllers.values) {
                  controller.clear();
                }
              },
              child: Text(I18n.tr('action.clear')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () {
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
    if (ok != true) return;
    await BackupService.wipeAll();
    if (!mounted) return;
    await _reloadAll();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(DataSettingsUiCopy.wipeSuccess)));
  }

  Future<void> _configureWebDavBackup() async {
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
      if (!mounted) return;
      setState(() => _webDavConfig = config);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.webDavConfigSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatWebDavSaveError(e))),
      );
    }
  }

  Future<void> _uploadWebDavBackup() async {
    if (!_webDavConfig.isConfigured) {
      await _configureWebDavBackup();
      if (!mounted) return;
      if (!_webDavConfig.isConfigured) return;
    }
    setState(() => _busy = true);
    try {
      final result = await WebDavBackupService().uploadCurrentBackup(
        _webDavConfig,
      );
      if (!mounted) return;
      setState(() => _busy = false);
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
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatWebDavUploadError(e))),
      );
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
    if (!_webDavConfig.isConfigured) {
      await _configureWebDavBackup();
      if (!mounted) return;
      if (!_webDavConfig.isConfigured) return;
    }
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
                  _webDavConfig.filename,
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
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final raw = await WebDavBackupService().downloadLatestBackup(
        _webDavConfig,
      );
      final count = await BackupService.importAll(
        raw,
        merge: merge,
        // 覆盖=还原到备份快照：备份中不存在的本机数据一并删除，弹窗已警告。
        // 服务层 `clearMissing && !merge` 守卫保证 merge 合并入口不受影响。
        clearMissing: true,
      );
      if (!mounted) return;
      await _reloadAll();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(DataSettingsUiCopy.webDavRestoreSuccess(merge, count)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.formatWebDavRestoreError(e))),
      );
    }
  }

  Future<void> _reloadAll() async {
    // 偏好键已纳入备份键集（BackupService._keys）：wipeAll/importAll 都会
    // 改写偏好存储，而根级 PreferencesProvider 的值缓存在内存字段，不重载
    // 会造成进程内偏好与存储分叉。与 main.dart 账号清理/云同步拉取一致：
    // 先 resetLocalState 作废在途读取并套用默认值，再 loadFromStorage 读回
    // 存储真值，最后把铃声偏好重放到原生设置（非 Android 为 no-op）。
    final preferencesProvider = context.read<PreferencesProvider>();
    preferencesProvider.resetLocalState();
    await preferencesProvider.loadFromStorage();
    await ReminderRingtoneSettings.applyPersistedSettingsToNative();
    if (!mounted) return;
    await Future.wait([
      context.read<TodoProvider>().loadFromStorage(),
      context.read<HabitProvider>().loadFromStorage(),
      context.read<PomodoroProvider>().loadFromStorage(),
      context.read<NoteProvider>().loadFromStorage(),
      context.read<AnniversaryProvider>().loadFromStorage(),
      context.read<DiaryProvider>().loadFromStorage(),
      context.read<GoalProvider>().loadFromStorage(),
      context.read<CourseProvider>().loadFromStorage(),
      context.read<UserProvider>().loadFromStorage(),
      context.read<TimeAuditProvider>().loadFromStorage(),
      context.read<AchievementProvider>().loadFromStorage(),
      context.read<ShareProvider>().load(),
      context.read<CalendarProvider>().loadFromStorage(),
      context.read<LocationReminderProvider>().loadFromStorage(),
      context.read<QuickCaptureTemplateProvider>().loadFromStorage(),
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
        final restoreFirst = widget.initialMode == BackupEntryMode.restore;
        final pageTitle = DataSettingsUiCopy.backupHeroTitle(restoreFirst);
        return Scaffold(
          backgroundColor: routeBackground,
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _activeExportedTitle(),
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.normal,
                                      color: cs.onSurface,
                                    ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _copy,
                              icon: const Icon(Icons.copy, size: 14),
                              label: Text(DataSettingsUiCopy.copyButton),
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
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: Text(
                        DataSettingsUiCopy.wipeButton,
                        style: const TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.shade300),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, VoidCallback onTap) {
    return ActionChip(
      avatar: const Icon(Icons.download, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
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
