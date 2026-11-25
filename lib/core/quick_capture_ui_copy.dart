import '../models/quick_capture_template.dart';
import '../models/todo.dart';
import 'i18n.dart';

/// Copy owned by the quick capture entry point and its feedback flows.
///
/// User supplied task, note, diary, template, and sync diagnostic text stays
/// untouched; only the surrounding product copy is localized here.
class QuickCaptureUiCopy {
  QuickCaptureUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;

  static String get aiCommandTitle => isEn ? 'AI commands' : 'AI 指令';
  static String get aiCommandHint => isEn
      ? 'Example: add a task tomorrow at 3 PM; save a note; start focus'
      : '例如：添加待办 明天下午3点买菜；记笔记 项目想法；开始专注';
  static String get templateTagsLabel => isEn ? 'Tags' : '标签';
  static String get templateTagsHint =>
      isEn ? 'Separate with commas or spaces' : '用逗号或空格分隔';
  static String defaultHabitUnit(int count) =>
      isEn ? (count <= 1 ? 'time' : 'times') : '次';

  static String get executeAction => isEn ? 'Run' : '执行';
  static String get quickCreateHeading => isEn ? 'Quick capture' : '快速创建';
  static String get fabOpenLabel =>
      isEn ? 'Open quick capture menu' : '打开快速创建菜单';
  static String get fabCloseLabel =>
      isEn ? 'Close quick capture menu' : '关闭快速创建菜单';
  static String get fabLongPressHint =>
      isEn ? 'Long press to open quick templates' : '长按打开快捷模板';

  static String get reminderRegistrationFailed =>
      isEn ? 'Reminder registration failed' : '待办提醒注册失败';
  static String get saveFailed =>
      isEn ? 'Could not save. Please try again.' : '保存失败，请重试。';
  static String get draftSaveFailed => isEn
      ? 'Could not save. Your draft is kept. Please try again.'
      : '保存失败，草稿已保留，请重试。';
  static String get todoSaving =>
      isEn ? 'Task is being saved. Please retry shortly.' : '待办正在保存中，请稍后重试';
  static String reminderSavedButNotRegistered(
    String issueTitle,
    String issue,
  ) => isEn
      ? '$issueTitle: task saved, but reminder was not registered: $issue'
      : '$issueTitle：待办已保存，但提醒未注册：$issue';
  static String get reminderRegistrationHint => isEn
      ? 'Reminder was not registered. Check notification permission, channel sound, and reminder time.'
      : '提醒未注册，请检查通知权限、渠道声音和提醒时间。';
  static String get alarmPermissionHint => isEn
      ? 'System notification permission is off, so the alarm was not registered. Enable it and save the reminder again.'
      : '系统通知权限未开启，闹钟提醒未注册。请开启通知权限后重新保存提醒。';
  static String issue(String title, String detail) =>
      isEn ? '$title: $detail' : '$title：$detail';

  static String get localSaved => isEn ? 'Saved on this device' : '待办已保存到本机';
  static String get localSavedFallback => isEn ? 'Saved locally' : '本机已保存';
  static String get syncPending =>
      isEn ? 'Cloud sync status is pending' : '云同步状态待确认';
  static String savedSyncPending(String savedText) =>
      isEn ? '$savedText. $syncPending' : '$savedText，$syncPending';
  static String reminderStatusHint(String syncMessage) => isEn
      ? '$syncMessage. Check reminder status in notification settings or task details.'
      : '$syncMessage；提醒状态可在通知设置/待办详情检查';

  static String aiCommandsExecuted({
    required int executed,
    required int total,
    required String syncMessage,
  }) {
    if (isEn) {
      if (executed == 1 && total == 1) {
        return 'One AI command executed. $syncMessage';
      }
      if (executed == total) {
        return '$total AI commands executed. $syncMessage';
      }
      return '$executed of $total AI commands executed. $syncMessage';
    }
    if (executed == 1 && total == 1) {
      return '已执行 1 条 AI 指令，$syncMessage';
    }
    if (executed == total) {
      return '已执行 $total 条 AI 指令，$syncMessage';
    }
    return '已执行 $executed/$total 条 AI 指令，$syncMessage';
  }

  static String aiReminderFailures(String base, int count) => isEn
      ? '$base. $count reminder(s) were not registered. Check notification settings or task details.'
      : '$base，其中 $count 条提醒未注册，请打开通知设置/待办详情检查';

  static String aiReminderStatus(String base, int count) => isEn
      ? '$base. Check $count reminder(s) in notification settings or task details.'
      : '$base，$count 条提醒状态可在通知设置/待办详情检查';

  static String commandExecuted(String title, String syncMessage) =>
      isEn ? '$title executed. $syncMessage' : '$title已执行，$syncMessage';

  static String todoCreatedMessage({
    required bool hasReminder,
    required String syncMessage,
  }) => hasReminder ? reminderStatusHint(syncMessage) : syncMessage;

  static String get habitCreatedMessage =>
      isEn ? 'Habit created from template' : '已按模板创建习惯';
  static String habitReminderFailed(String issue) => isEn
      ? 'Habit created, but reminder was not registered: $issue'
      : '习惯已创建，但提醒未注册：$issue';
  static String templateName(QuickCaptureTemplate template) {
    if (!isEn || !template.builtIn) return template.name;
    return switch (template.id) {
      'builtin-work-meeting' => 'Work meeting',
      'builtin-shopping' => 'Shopping list',
      'builtin-reading-habit' => 'Daily reading',
      _ => template.name,
    };
  }

  static String templateSummary(QuickCaptureTemplate template) {
    if (template.kind == QuickCaptureTemplateKind.habit) {
      final kind = isEn ? 'Habit' : '习惯';
      final unit = _templateValue(
        template,
        template.habitUnit?.trim().isNotEmpty == true
            ? template.habitUnit!
            : defaultHabitUnit(template.habitTargetCount),
      );
      final time = template.habitRemind && template.habitRemindHour != null
          ? ' · ${template.habitRemindHour!.toString().padLeft(2, '0')}:${(template.habitRemindMinute ?? 0).toString().padLeft(2, '0')}'
          : '';
      return '$kind · ${template.habitTargetCount} $unit$time'
          '${template.habitCategory == null ? '' : ' · ${_templateValue(template, template.habitCategory!)}'}';
    }
    final parts = <String>[
      if (template.listGroupName?.trim().isNotEmpty == true)
        _templateValue(template, template.listGroupName!.trim()),
      if (template.priority != TodoPriority.none) template.priority.label,
      if (template.tags.isNotEmpty)
        template.tags
            .map((tag) => '#${_templateValue(template, tag)}')
            .join(' '),
      if (template.reminderPlan.enabled &&
          template.reminderPlan.rules.isNotEmpty)
        isEn ? 'With reminder' : '含提醒',
    ];
    return parts.isEmpty
        ? (isEn ? 'Task template' : '待办模板')
        : parts.join(' · ');
  }

  static String _templateValue(QuickCaptureTemplate template, String value) {
    if (!isEn || !template.builtIn) return value;
    final labels = switch (template.id) {
      'builtin-work-meeting' => const {'工作': 'Work', '会议': 'Meeting'},
      'builtin-shopping' => const {'购物': 'Shopping'},
      'builtin-reading-habit' => const {'分钟': 'minutes', '学习提升': 'Learning'},
      _ => const <String, String>{},
    };
    return labels[value] ?? value;
  }
}
