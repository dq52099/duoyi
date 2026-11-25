import '../models/time_entry.dart';
import 'i18n.dart';

class TimeAuditUiCopy {
  TimeAuditUiCopy._();

  static bool get _en => I18n.current == AppLocale.en;

  static String get stopwatchTitle => _en ? 'Live Stopwatch' : '实时计时器';

  static String get statusRunning => _en ? 'Running' : '计时中';
  static String get statusPaused => _en ? 'Paused' : '已暂停';
  static String get statusReady => _en ? 'Ready' : '就绪';

  static String get start => _en ? 'Start' : '开始计时';
  static String get pause => _en ? 'Pause' : '暂停';
  static String get resume => _en ? 'Resume' : '继续';
  static String get stopAndSave => _en ? 'Stop & Save' : '停止并记录';
  static String get discard => _en ? 'Discard' : '重置';

  static String get renameLabelTooltip =>
      _en ? 'Rename session label' : '编辑计时名称';
  static String get renameDialogTitle =>
      _en ? 'Session Label' : '设置计时活动名称';
  static String get renameDialogHint =>
      _en ? 'e.g. Deep coding or English reading' : '例如：深度编码、英语阅读';
  static String get clearLabel => _en ? 'Use Default' : '使用默认名称';

  static String defaultSessionLabel(TimeEntryCategory category) => _en
      ? '${category.label} session'
      : '${category.label}计时';

  static String get stopwatchRecordedNote =>
      _en ? 'Recorded via live stopwatch' : '来自实时计时器记录';

  static String recordedSaved(String title) =>
      _en ? 'Saved time entry: $title' : '已记录时间足迹：$title';

  static String get exportCsvTooltip =>
      _en ? 'Export CSV' : '导出 CSV';

  static String csvExported(String fileName) =>
      _en ? 'Exported CSV: $fileName' : '已导出 CSV：$fileName';

  static String get csvCopiedFallback =>
      _en ? 'CSV copied to clipboard' : 'CSV 已复制到剪贴板';

  static String get copyCsvAction => _en ? 'Copy CSV' : '复制 CSV';

  static String get highlightedBadge => _en ? 'Focused' : '已定位';
}
