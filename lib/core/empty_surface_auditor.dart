/// 空架子扫描器（Task 19.1 / Requirements 9.1, 9.2）。
///
/// 用途：
/// - 把"只做了占位界面 / 假数据 / TODO / 空 build" 的已知位点集中编目，
///   供 `docs/empty-surface-audit.md` 生成 backlog、也供 QA 快速定位。
/// - 修复某条后把 `fixTicketId` 填上对应的 `tasks.md` 任务 id，形成双向追溯。
///
/// 不扫运行时 UI —— 静态 meta 由人工 + `scripts/empty_surface_scan.sh`
/// 共同维护。运行时辅助 `runtimeAudit` 留在本文件以便未来扩展。
library;

import 'package:flutter/widgets.dart';

/// 一条已知的"空架子"条目。
class EmptySurfaceEntry {
  /// 相对仓库根的文件路径（用正斜杠）。
  final String file;

  /// 人类可读的占位原因。
  final String reason;

  /// 修复条目对应的任务 id（如 `19.1`、`22.2`）；未修复时为 null。
  final String? fixTicketId;

  const EmptySurfaceEntry({
    required this.file,
    required this.reason,
    this.fixTicketId,
  });

  @override
  String toString() =>
      '$file: $reason${fixTicketId == null ? '' : ' [$fixTicketId]'}';
}

/// 空架子扫描器。
class EmptySurfaceAuditor {
  EmptySurfaceAuditor._();

  /// 已知占位清单。维护规则：
  /// - 新发现的空架子追加到这里；
  /// - 修复之后填上 `fixTicketId` 但保留历史条目，方便未来回溯；
  /// - 完全消失的文件可删除条目（由 grep 扫描保护回归）。
  static const List<EmptySurfaceEntry> known = <EmptySurfaceEntry>[
    EmptySurfaceEntry(
      file: 'lib/services/audio_service.dart',
      reason: '旧版 AudioService 只切内存标记，不播真实音频',
      fixTicketId: '15.4', // 已由 FocusSoundService 替代，旧类保留为 deprecated shim
    ),
    EmptySurfaceEntry(
      file: 'lib/screens/today_screen.dart',
      reason: "今日页多个 section 的 '查看' 按钮原直接 push，遇空数据黑屏",
      fixTicketId: '17', // TodayDetailRouter 统一入口
    ),
    EmptySurfaceEntry(
      file: 'lib/services/recurrence_engine.dart',
      reason:
          'RecurrenceEngine 已实现，编辑页"下一派发日"已切到 RecurrenceEngine.nextOccurrence',
      fixTicketId: '22.1', // M0 修复：goal_edit_screen 已集成 RecurrenceEngine
    ),
    EmptySurfaceEntry(
      file: 'lib/services/holiday_calendar.dart',
      reason: 'HolidayCalendar 内置数据已覆盖 2024-2026；后续年份通过 updateFrom 注入',
      fixTicketId: '21', // M0 修复：补齐 2026 节假日数据
    ),
    EmptySurfaceEntry(
      file: 'lib/widgets/result_states.dart',
      reason: 'EmptyState / LoadingState / ErrorState 三件套已实现',
      fixTicketId: '20', // result_states.dart 已提供完整三件套
    ),
    EmptySurfaceEntry(
      file: 'backend/main.py',
      reason: '后端 cloud_sync_v2 接口字段与新 Goal/Todo 结构对齐工作进行中',
      fixTicketId: '23.3',
    ),
  ];

  /// 返回仍有 `fixTicketId` 但没说明已关闭的条目。
  ///
  /// 注意：这里采用的是"条目一旦登记就视为已跟踪"的约定，所以"open"
  /// 对应的其实是 **没有 fixTicketId** 的条目。
  static List<EmptySurfaceEntry> openEntries() =>
      known.where((e) => e.fixTicketId == null).toList(growable: false);

  /// 运行时探测占位（当前为占位实现）。
  ///
  /// 未来可接入 `Service Locator` 遍历已注册 Screen，嗅探 "data=empty
  /// 但 UI 只渲染 Text(\"TODO\")" 之类的运行时特征。留接口不留实现，
  /// 避免无意义的常驻开销。
  static Future<EmptyAuditReport> runtimeAudit(BuildContext context) async {
    return EmptyAuditReport(
      knownEntries: known,
      runtimeFindings: const <String>[],
    );
  }
}

/// `runtimeAudit` 的汇总结果。
class EmptyAuditReport {
  final List<EmptySurfaceEntry> knownEntries;

  /// 运行时检测到的可疑位点（目前留空，等未来扩展填入）。
  final List<String> runtimeFindings;

  const EmptyAuditReport({
    required this.knownEntries,
    required this.runtimeFindings,
  });

  int get totalIssues => knownEntries.length + runtimeFindings.length;

  @override
  String toString() =>
      'EmptyAuditReport(known=${knownEntries.length}, runtime=${runtimeFindings.length})';
}
