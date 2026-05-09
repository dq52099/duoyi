import 'package:uuid/uuid.dart';

import 'recurrence.dart';

const _uuid = Uuid();

/// 目标分类（与推荐目标库一致）。
///
/// 旧版 JSON 中可能以 `String?` 保存分类名（例如 'health'），
/// 迁移时会按名称匹配；匹配不到则回退到 [GoalCategory.custom]。
enum GoalCategory { recommend, health, study, sport, emotion, custom }

/// 调度模式：固定日期 vs 在区间内随机派发。
enum SchedulingMode { fixed, random }

/// 提醒类型：
/// - [ReminderKind.push] 走通知通道（`duoyi_general`）。
/// - [ReminderKind.alarm] 走闹钟通道（`duoyi_alarm`，全屏 / 高优先级）。
enum ReminderKind { push, alarm }

/// 目标调度策略：结合 [RecurrenceRule] 决定具体派发日期。
///
/// - `fixed` 模式：配合 `fixedWeekdays`（周重复）或 `fixedMonthDays`（月重复）
///   指定具体星期或日期。
/// - `random` 模式：在 `[anchor + randomMinGapDays, upperBound]` 之间按稳定
///   种子随机采样；`randomMaxPerWeek` / `randomMaxPerMonth` 控制派发上限。
class GoalScheduling {
  final SchedulingMode mode;
  final List<int>? fixedWeekdays;
  final List<int>? fixedMonthDays;
  final int? randomMinGapDays;
  final int? randomMaxPerWeek;
  final int? randomMaxPerMonth;

  const GoalScheduling({
    required this.mode,
    this.fixedWeekdays,
    this.fixedMonthDays,
    this.randomMinGapDays,
    this.randomMaxPerWeek,
    this.randomMaxPerMonth,
  });

  /// 固定模式的便捷构造；可选传入固定的星期 / 月日。
  const GoalScheduling.fixed({
    List<int>? fixedWeekdays,
    List<int>? fixedMonthDays,
  }) : this(
          mode: SchedulingMode.fixed,
          fixedWeekdays: fixedWeekdays,
          fixedMonthDays: fixedMonthDays,
        );

  /// 随机模式的便捷构造。
  const GoalScheduling.random({
    int minGapDays = 1,
    int? maxPerWeek,
    int? maxPerMonth,
  }) : this(
          mode: SchedulingMode.random,
          randomMinGapDays: minGapDays,
          randomMaxPerWeek: maxPerWeek,
          randomMaxPerMonth: maxPerMonth,
        );

  GoalScheduling copyWith({
    SchedulingMode? mode,
    List<int>? fixedWeekdays,
    List<int>? fixedMonthDays,
    int? randomMinGapDays,
    int? randomMaxPerWeek,
    int? randomMaxPerMonth,
  }) =>
      GoalScheduling(
        mode: mode ?? this.mode,
        fixedWeekdays: fixedWeekdays ?? this.fixedWeekdays,
        fixedMonthDays: fixedMonthDays ?? this.fixedMonthDays,
        randomMinGapDays: randomMinGapDays ?? this.randomMinGapDays,
        randomMaxPerWeek: randomMaxPerWeek ?? this.randomMaxPerWeek,
        randomMaxPerMonth: randomMaxPerMonth ?? this.randomMaxPerMonth,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.index,
        'fixedWeekdays': fixedWeekdays,
        'fixedMonthDays': fixedMonthDays,
        'randomMinGapDays': randomMinGapDays,
        'randomMaxPerWeek': randomMaxPerWeek,
        'randomMaxPerMonth': randomMaxPerMonth,
      };

  factory GoalScheduling.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const GoalScheduling.fixed();
    final rawMode = json['mode'];
    final mode = _enumFromIndex(
          SchedulingMode.values,
          rawMode is num ? rawMode.toInt() : null,
        ) ??
        SchedulingMode.fixed;
    return GoalScheduling(
      mode: mode,
      fixedWeekdays: (json['fixedWeekdays'] as List?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      fixedMonthDays: (json['fixedMonthDays'] as List?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      randomMinGapDays: (json['randomMinGapDays'] as num?)?.toInt(),
      randomMaxPerWeek: (json['randomMaxPerWeek'] as num?)?.toInt(),
      randomMaxPerMonth: (json['randomMaxPerMonth'] as num?)?.toInt(),
    );
  }
}

/// 提醒配置：目标 / 任务 / 习惯共用。
///
/// `enabled = false` 时所有其它字段仅作为"最后一次设置"的记忆，
/// 不会触发任何系统提醒。
class ReminderConfig {
  final bool enabled;
  final ReminderKind kind;
  final int? hour;
  final int? minute;
  final int daysBefore;
  final bool vibrate;
  final bool fullScreen;

  const ReminderConfig({
    this.enabled = false,
    this.kind = ReminderKind.alarm,
    this.hour,
    this.minute,
    this.daysBefore = 0,
    this.vibrate = true,
    this.fullScreen = true,
  });

  /// 未启用的默认值。
  const ReminderConfig.disabled() : this(enabled: false);

  ReminderConfig copyWith({
    bool? enabled,
    ReminderKind? kind,
    int? hour,
    int? minute,
    int? daysBefore,
    bool? vibrate,
    bool? fullScreen,
  }) =>
      ReminderConfig(
        enabled: enabled ?? this.enabled,
        kind: kind ?? this.kind,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        daysBefore: daysBefore ?? this.daysBefore,
        vibrate: vibrate ?? this.vibrate,
        fullScreen: fullScreen ?? this.fullScreen,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'kind': kind.index,
        'hour': hour,
        'minute': minute,
        'daysBefore': daysBefore,
        'vibrate': vibrate,
        'fullScreen': fullScreen,
      };

  factory ReminderConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReminderConfig.disabled();
    final rawKind = json['kind'];
    final kind = _enumFromIndex(
          ReminderKind.values,
          rawKind is num ? rawKind.toInt() : null,
        ) ??
        ReminderKind.alarm;
    return ReminderConfig(
      enabled: json['enabled'] == true,
      kind: kind,
      hour: (json['hour'] as num?)?.toInt(),
      minute: (json['minute'] as num?)?.toInt(),
      daysBefore: (json['daysBefore'] as num?)?.toInt() ?? 0,
      vibrate: json['vibrate'] ?? true,
      fullScreen: json['fullScreen'] ?? true,
    );
  }
}

/// 专注（番茄钟）联动配置。
class FocusLink {
  final bool enabled;
  final String? presetId;
  final int? focusSeconds;
  final String whiteNoise;

  const FocusLink({
    this.enabled = false,
    this.presetId,
    this.focusSeconds,
    this.whiteNoise = 'none',
  });

  /// 未启用的默认值。
  const FocusLink.disabled() : this(enabled: false);

  FocusLink copyWith({
    bool? enabled,
    String? presetId,
    int? focusSeconds,
    String? whiteNoise,
  }) =>
      FocusLink(
        enabled: enabled ?? this.enabled,
        presetId: presetId ?? this.presetId,
        focusSeconds: focusSeconds ?? this.focusSeconds,
        whiteNoise: whiteNoise ?? this.whiteNoise,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'presetId': presetId,
        'focusSeconds': focusSeconds,
        'whiteNoise': whiteNoise,
      };

  factory FocusLink.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FocusLink.disabled();
    return FocusLink(
      enabled: json['enabled'] == true,
      presetId: json['presetId'] as String?,
      focusSeconds: (json['focusSeconds'] as num?)?.toInt(),
      whiteNoise: (json['whiteNoise'] as String?) ?? 'none',
    );
  }
}

/// 目标里程碑
class GoalMilestone {
  String id;
  String title;
  bool isCompleted;
  DateTime? completedAt;

  GoalMilestone({
    String? id,
    required this.title,
    this.isCompleted = false,
    this.completedAt,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        'completedAt': completedAt?.toIso8601String(),
      };

  factory GoalMilestone.fromJson(Map<String, dynamic> json) => GoalMilestone(
        id: json['id'],
        title: json['title'] ?? '',
        isCompleted: json['isCompleted'] ?? false,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'])
            : null,
      );
}

enum GoalStatus { active, paused, achieved, abandoned }

/// 长期目标
class GoalItem {
  final String id;
  String title;
  String description;
  String icon;
  int colorValue;
  DateTime? startDate;
  DateTime? targetDate;
  GoalStatus status;
  double progress; // 0.0 - 1.0，自动算或手动
  bool autoProgress; // true=由里程碑计算，false=手动
  List<GoalMilestone> milestones;
  GoalCategory category;
  RecurrenceRule recurrence;
  GoalScheduling scheduling;
  bool skipHolidays;
  FocusLink focusLink;
  ReminderConfig reminder;
  int? timeTargetSeconds;
  int? dailyTargetCount;
  int sortOrder;
  DateTime createdAt;
  DateTime updatedAt;

  GoalItem({
    String? id,
    required this.title,
    this.description = '',
    this.icon = 'flag',
    this.colorValue = 0xFFFFA726,
    this.startDate,
    this.targetDate,
    this.status = GoalStatus.active,
    this.progress = 0,
    this.autoProgress = true,
    List<GoalMilestone>? milestones,
    this.category = GoalCategory.custom,
    RecurrenceRule? recurrence,
    GoalScheduling? scheduling,
    this.skipHolidays = false,
    FocusLink? focusLink,
    ReminderConfig? reminder,
    this.timeTargetSeconds,
    this.dailyTargetCount,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        milestones = milestones ?? [],
        recurrence = recurrence ?? const RecurrenceRule(),
        scheduling = scheduling ?? const GoalScheduling.fixed(),
        focusLink = focusLink ?? const FocusLink.disabled(),
        reminder = reminder ?? const ReminderConfig.disabled(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get computedProgress {
    if (!autoProgress) return progress;
    if (milestones.isEmpty) return status == GoalStatus.achieved ? 1.0 : 0.0;
    final done = milestones.where((m) => m.isCompleted).length;
    return (done / milestones.length).clamp(0.0, 1.0);
  }

  int get daysRemaining {
    if (targetDate == null) return -1;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final t = DateTime(targetDate!.year, targetDate!.month, targetDate!.day);
    return t.difference(today).inDays;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'icon': icon,
        'colorValue': colorValue,
        'startDate': startDate?.toIso8601String(),
        'targetDate': targetDate?.toIso8601String(),
        'status': status.index,
        'progress': progress,
        'autoProgress': autoProgress,
        'milestones': milestones.map((m) => m.toJson()).toList(),
        'category': category.name,
        'recurrence': recurrence.toJson(),
        'scheduling': scheduling.toJson(),
        'skipHolidays': skipHolidays,
        'focusLink': focusLink.toJson(),
        'reminder': reminder.toJson(),
        'timeTargetSeconds': timeTargetSeconds,
        'dailyTargetCount': dailyTargetCount,
        'sortOrder': sortOrder,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory GoalItem.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return GoalItem(
      id: json['id'],
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      icon: json['icon'] ?? 'flag',
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFFFFA726,
      startDate: json['startDate'] != null
          ? DateTime.tryParse(json['startDate'].toString())
          : null,
      targetDate: json['targetDate'] != null
          ? DateTime.tryParse(json['targetDate'].toString())
          : null,
      status: _enumFromIndex(
            GoalStatus.values,
            (json['status'] as num?)?.toInt(),
          ) ??
          GoalStatus.active,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      autoProgress: json['autoProgress'] ?? true,
      milestones: (json['milestones'] as List<dynamic>?)
              ?.map((m) => GoalMilestone.fromJson(m))
              .toList() ??
          [],
      category: _parseGoalCategory(json['category']),
      recurrence: RecurrenceRule.fromJson(
        json['recurrence'] as Map<String, dynamic>?,
      ),
      scheduling: GoalScheduling.fromJson(
        json['scheduling'] as Map<String, dynamic>?,
      ),
      skipHolidays: json['skipHolidays'] == true,
      focusLink: FocusLink.fromJson(
        json['focusLink'] as Map<String, dynamic>?,
      ),
      reminder: ReminderConfig.fromJson(
        json['reminder'] as Map<String, dynamic>?,
      ),
      timeTargetSeconds: (json['timeTargetSeconds'] as num?)?.toInt(),
      dailyTargetCount: (json['dailyTargetCount'] as num?)?.toInt(),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null
          ? (DateTime.tryParse(json['createdAt'].toString()) ?? now)
          : now,
      updatedAt: json['updatedAt'] != null
          ? (DateTime.tryParse(json['updatedAt'].toString()) ?? now)
          : now,
    );
  }
}

/// 把旧版 `category: String?`（如 `'health'`、`'自定义'`）迁移到新的
/// [GoalCategory] 枚举：
/// - `null` / 空串 → [GoalCategory.custom]
/// - 整数 / 数值字符串 → 按 index 匹配
/// - 字符串 → 按枚举 `name` 大小写不敏感匹配，匹配不到回退 custom。
GoalCategory _parseGoalCategory(dynamic raw) {
  if (raw == null) return GoalCategory.custom;
  if (raw is num) {
    return _enumFromIndex(GoalCategory.values, raw.toInt()) ??
        GoalCategory.custom;
  }
  if (raw is String) {
    final s = raw.trim();
    if (s.isEmpty) return GoalCategory.custom;
    final asInt = int.tryParse(s);
    if (asInt != null) {
      return _enumFromIndex(GoalCategory.values, asInt) ??
          GoalCategory.custom;
    }
    final lower = s.toLowerCase();
    for (final c in GoalCategory.values) {
      if (c.name.toLowerCase() == lower) return c;
    }
  }
  return GoalCategory.custom;
}

T? _enumFromIndex<T>(List<T> values, int? index) {
  if (index == null) return null;
  if (index < 0 || index >= values.length) return null;
  return values[index];
}
