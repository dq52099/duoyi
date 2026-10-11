import 'i18n.dart';

/// 待办详情页与编辑面板统一文案（中英双语）。
///
/// 遵循全局文案设计原则：
/// - 每次 getter / function 调用动态读取 [I18n.current]，禁止在 static / init 中缓存翻译。
/// - 用户自定义内容（如待办标题、备注正文、标签名、协作评论）保留原始字符，仅翻译 app-owned 文案。
/// - 零依赖循环：不引入数据模型或 Provider，保持纯文案层。
class TodoDetailUiCopy {
  TodoDetailUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;
  static bool get isZh => I18n.current == AppLocale.zh;

  // ---------------------------------------------------------------------------
  // 页面标题与导航操作 (Page Title & Navigation)
  // ---------------------------------------------------------------------------
  static String get screenTitle => isEn ? 'Task Details' : '任务详情';
  static String get taskNotFound =>
      isEn ? 'This task does not exist or has been deleted' : '这个任务不存在或已被删除';
  static String get back => isEn ? 'Back' : '返回';
  static String get save => isEn ? 'Save' : '保存';

  // ---------------------------------------------------------------------------
  // 通用操作 (Common Actions)
  // ---------------------------------------------------------------------------
  static String get cancel => isEn ? 'Cancel' : '取消';
  static String get add => isEn ? 'Add' : '添加';
  static String get clear => isEn ? 'Clear' : '清除';

  // ---------------------------------------------------------------------------
  // 任务基础字段与校验 (Task Fields & Validation)
  // ---------------------------------------------------------------------------
  static String get taskTitleLabel => isEn ? 'Task title' : '任务名称';
  static String get taskTitleEmptyError =>
      isEn ? 'Task title cannot be empty' : '任务名称不能为空';
  static String get sharedSpaceReadOnlyError =>
      isEn ? 'You only have view permission in this shared space' : '你在这个共享空间中只有查看权限';
  static String get saveInProgressError =>
      isEn ? 'Todo is saving, please try again later.' : '待办正在保存中，请稍后重试。';
  static String saveFailed(String error) =>
      isEn ? 'Save failed: $error' : '保存失败：$error';
  static String savedWithoutReminder(String issue) =>
      isEn ? 'Todo saved, but reminder not scheduled: $issue' : '待办已保存，但提醒未注册：$issue';

  // ---------------------------------------------------------------------------
  // 放弃修改对话框 (Discard Changes Dialog)
  // ---------------------------------------------------------------------------
  static String get discardDialogTitle =>
      isEn ? 'Discard unsaved changes?' : '放弃未保存的修改？';
  static String get discardDialogContent => isEn
      ? 'Current changes are not saved. Returning will discard them.'
      : '当前修改尚未保存，返回将丢弃这些改动。';
  static String get discardAction => isEn ? 'Discard' : '放弃';

  // ---------------------------------------------------------------------------
  // 四象限 (Eisenhower Quadrant)
  // ---------------------------------------------------------------------------
  static String get quadrantLabel => isEn ? 'Quadrant' : '四象限';
  static String get quadrantQ1 => isEn ? 'Q1 Urgent & Important' : 'Q1 重要且紧急';
  static String get quadrantQ2 =>
      isEn ? 'Q2 Important, Not Urgent' : 'Q2 重要不紧急';
  static String get quadrantQ3 =>
      isEn ? 'Q3 Urgent, Not Important' : 'Q3 紧急不重要';
  static String get quadrantQ4 =>
      isEn ? 'Q4 Not Urgent, Not Important' : 'Q4 不重要不紧急';

  // ---------------------------------------------------------------------------
  // 优先级 (Priority)
  // ---------------------------------------------------------------------------
  static String get prioritySection => isEn ? 'Priority' : '优先级';

  // ---------------------------------------------------------------------------
  // 截止日期与重复 (Due Date & Recurrence)
  // ---------------------------------------------------------------------------
  static String get dueDateTileTitle => isEn ? 'Due date' : '截止日期';
  static String get dueDateNotSet => isEn ? 'Not set' : '未设置';
  static String get dueDatePickerTitle => isEn ? 'Due Date' : '截止日期';
  static String get dueDatePickerSubtitle =>
      isEn ? 'Select task date with unified calendar' : '使用统一日历选择任务日期';
  static String get repeatTileTitle => isEn ? 'Repeat' : '重复';

  // ---------------------------------------------------------------------------
  // 共享负责人 (Shared Assignee)
  // ---------------------------------------------------------------------------
  static String get assigneeLabel => isEn ? 'Assignee' : '负责人';
  static String get assigneePrivateSubtitle => isEn
      ? 'Private tasks need no assignment; choose members in shared lists'
      : '私有任务无需指派；共享清单任务可选择成员';
  static String sharedSpaceHelper(String spaceName) =>
      isEn ? 'Shared space: $spaceName' : '共享空间：$spaceName';
  static String get unassigned => isEn ? 'Unassigned' : '未指派';

  // ---------------------------------------------------------------------------
  // 任务评论 (Task Comments)
  // ---------------------------------------------------------------------------
  static String get taskCommentsTitle => isEn ? 'Task comments' : '任务评论';
  static String get commentHint => isEn
      ? 'Log progress or risks for this task; @username/email/nickname to notify'
      : '针对这个任务记录进展或风险，@用户名/邮箱/昵称 可提醒对方';
  static String get sendCommentTooltip => isEn ? 'Send comment' : '发送评论';
  static String get noComments => isEn ? 'No task comments yet' : '暂无任务评论';
  static String commentSendFailed(String error) =>
      isEn ? 'Failed to send comment: $error' : '评论发送失败: $error';
  static String get shareServiceUnavailableFallback => isEn
      ? 'Shared space service is temporarily unavailable. Please try again later or contact admin.'
      : '共享空间服务暂不可用，请稍后重试或联系管理员';

  // ---------------------------------------------------------------------------
  // 提醒与权限提示 (Reminders & Health Preflight)
  // ---------------------------------------------------------------------------
  static String get reminderTitle => isEn ? 'Reminder' : '提醒';
  static String get reminderRegisterFailedIssueTitle =>
      isEn ? 'Failed to schedule todo reminder' : '待办提醒注册失败';
  static String reminderPreflightUnregistered(String issueTitle) => isEn
      ? '$issueTitle: Reminder not scheduled. Please check notification permissions, channel sound, and reminder time.'
      : '$issueTitle：提醒未注册，请检查通知权限、渠道声音和提醒时间。';
  static String get alarmPermissionDenied => isEn
      ? 'Alarm reminder registration failed: System notification permission is disabled. Please enable notification permission and save again.'
      : '闹钟提醒注册失败：系统通知权限未开启，提醒未注册。请开启通知权限后重新保存提醒。';
  static String get normalChannelNotReadyWarning => isEn
      ? 'Standard notification channel is not ready; alerts may not pop up on time'
      : '普通提醒渠道未就绪，到点可能不会弹出系统通知';
  static String get alarmInitFailed => isEn
      ? 'Alarm reminder setup failed. Please check notifications, exact alarm, full-screen intent, and background running permissions and try again.'
      : '闹钟提醒准备失败，请检查通知、精准闹钟、全屏提醒和后台运行权限后重试。';
  static String get alarmChannelNotReadyWarning => isEn
      ? 'Alarm notification channel is not ready; alerts may not pop up on time'
      : '强提醒渠道未就绪，到点可能不会弹出闹钟通知';
  static String get exactAlarmDenied => isEn
      ? 'Alarm reminder registration failed: Exact alarm permission is disabled. Please enable it in system settings and try again.'
      : '闹钟提醒注册失败：精准闹钟权限未开启，无法可靠注册锁屏闹钟。请在系统设置开启后重试。';
  static String get fullScreenIntentDenied => isEn
      ? 'Alarm reminder registration failed: Full-screen intent permission is disabled. Please enable it in system settings and try again.'
      : '闹钟提醒注册失败：全屏提醒权限未开启，锁屏时无法弹出闹钟。请在系统设置开启后重试。';
  static String reminderWarnings(String issueTitle, List<String> warnings) =>
      isEn
          ? '$issueTitle: ${warnings.join("; ")}.'
          : '$issueTitle：${warnings.join("；")}。';
  static String get unableToOpenSettings =>
      isEn ? 'Unable to open system settings' : '无法打开系统设置';

  // ---------------------------------------------------------------------------
  // 位置提醒 (Location Reminders)
  // ---------------------------------------------------------------------------
  static String get locationReminderTitle =>
      isEn ? 'Location Reminder' : '位置提醒';
  static String get locationReminderSubtitle => isEn
      ? 'Set reminders when arriving at or leaving a location'
      : '可为这条任务设置到达或离开某地时提醒';
  static String get addLocationReminderDialogTitle =>
      isEn ? 'Add Location Reminder' : '添加位置提醒';
  static String get locationReminderTitleLabel =>
      isEn ? 'Reminder title' : '提醒标题';
  static String get locationReminderNotesLabel => isEn ? 'Notes' : '备注';
  static String get latitudeLabel => isEn ? 'Latitude' : '纬度';
  static String get longitudeLabel => isEn ? 'Longitude' : '经度';
  static String get radiusLabel => isEn ? 'Radius (meters)' : '半径（米）';
  static String get arriveTrigger => isEn ? 'Arrive' : '到达';
  static String get leaveTrigger => isEn ? 'Leave' : '离开';
  static String get triggerDirectionLabel => isEn ? 'Trigger direction' : '触发方向';
  static String get autoCloseAfterTrigger =>
      isEn ? 'Turn off after triggered' : '触发后自动关闭';
  static String get invalidLocationCoordinates =>
      isEn ? 'Please enter a title and valid coordinates' : '请输入标题和有效经纬度';
  static String get locationReminderAdded =>
      isEn ? 'Location reminder added' : '已添加任务位置提醒';
  static String get deleteLocationReminderTooltip =>
      isEn ? 'Delete location reminder' : '删除位置提醒';

  // ---------------------------------------------------------------------------
  // Markdown 描述与工具栏 (Markdown Description & Toolbar)
  // ---------------------------------------------------------------------------
  static String get descriptionSection => isEn ? 'Description' : '任务描述';
  static String get editDescriptionTooltip =>
      isEn ? 'Edit description' : '编辑描述';
  static String get previewDescriptionTooltip =>
      isEn ? 'Preview description' : '预览描述';
  static String get markdownHint =>
      isEn ? 'Markdown description supported' : '支持 Markdown 描述';
  static String get markdownHeading => isEn ? 'Heading' : '标题';
  static String get markdownBold => isEn ? 'Bold' : '加粗';
  static String get markdownItalic => isEn ? 'Italic' : '斜体';
  static String get markdownQuote => isEn ? 'Quote' : '引用';
  static String get markdownBullet => isEn ? 'List' : '列表';
  static String get markdownChecklist => isEn ? 'Checklist' : '清单';
  static String get markdownCode => isEn ? 'Code' : '代码';
  static String get markdownLink => isEn ? 'Link' : '链接';
  static String get markdownLinkPlaceholder => isEn ? 'Link' : '链接';
  static String get noDescription => isEn ? 'No description' : '暂无描述';

  // ---------------------------------------------------------------------------
  // 目标时长 (Target Duration)
  // ---------------------------------------------------------------------------
  static String get targetDurationSection =>
      isEn ? 'Target Duration' : '目标时长';
  static String get targetDurationHint =>
      isEn ? 'Minutes (0 or empty to clear)' : '分钟（0 或空 = 清除）';
  static String get minutesSuffix => isEn ? 'min' : '分钟';
  static String presetMinutes(int minutes) =>
      isEn ? '$minutes min' : '$minutes 分钟';

  // ---------------------------------------------------------------------------
  // 标签 (Tags)
  // ---------------------------------------------------------------------------
  static String get tagsSection => isEn ? 'Tags' : '标签';
  static String get newTagHint => isEn ? '+ New tag' : '+ 新标签';

  // ---------------------------------------------------------------------------
  // 子任务 (Subtasks)
  // ---------------------------------------------------------------------------
  static String get subtasksSection => isEn ? 'Subtasks' : '子任务';
  static String get addSubtaskLabel => isEn ? 'Add subtask' : '新增子任务';

  // ---------------------------------------------------------------------------
  // 附件 (Attachments)
  // ---------------------------------------------------------------------------
  static String get attachmentsSection => isEn ? 'Attachments' : '附件';
  static String get pickFileTooltip => isEn ? 'Choose file' : '选择文件';
  static String get addLinkTooltip => isEn ? 'Add link' : '添加链接';
  static String get noAttachments => isEn ? 'No attachments' : '暂无附件';
  static String get addAttachmentLinkDialogTitle =>
      isEn ? 'Add attachment link' : '添加附件链接';
  static String get attachmentNameLabel => isEn ? 'Name' : '名称';
  static String get attachmentUriLabel =>
      isEn ? 'Link or local path' : '链接或本地路径';
  static String get attachmentMimeLabel => isEn ? 'Type (optional)' : '类型（可选）';
  static String get defaultAttachmentName => isEn ? 'Attachment' : '附件';
}
