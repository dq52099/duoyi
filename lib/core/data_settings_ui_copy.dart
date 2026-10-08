import 'dart:io';
import 'dart:async';
import 'i18n.dart';
import '../services/api_client.dart';

/// 数据设置（备份/导入/导出/WebDAV）与主题装扮/奖励设置专用文案字典与异常本地化格式化工具。
///
/// 遵循设计规范：
/// 1. 不暴露底层技术细节、堆栈、原始异常或凭据（如 WebDAV 密码与 Token）。
/// 2. 错误文案具备明确可操作性，指导用户下一步操作。
/// 3. 支持中英双语，实时响应 [I18n.current] 与 [I18n.localeListenable]。
/// 4. 内置奖励装饰（番茄钟背景、头像框、卡片皮肤）名称与描述仅在展示层按稳定 ID 本地化，
///    不改写持久化记录与后端传输内容。
class DataSettingsUiCopy {
  DataSettingsUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;

  // --- 通用动作与反馈 ---
  static String get gotIt => isEn ? 'Got it' : '知道了';
  static String get confirmImport => isEn ? 'Confirm Import' : '确认导入';
  static String get selectFile => isEn ? 'Select File' : '选择文件';
  static String get startRestore => isEn ? 'Start Restore' : '开始恢复';
  static String get undoImport => isEn ? 'Undo This Import' : '撤销本次导入';
  static String get undoImportSuccess => isEn ? 'Import undone' : '已撤销本次导入';
  static String get copiedToClipboard =>
      isEn ? 'Copied to clipboard' : '已复制到剪贴板';
  static String get exportContent => isEn ? 'Exported Content' : '导出内容';
  static String get copyButton => isEn ? 'Copy' : '复制';
  static String get fullBackupJsonTitle =>
      isEn ? 'Full Backup (JSON)' : '全量备份 (JSON)';

  // --- 备份与恢复页面 ---
  static String get backupPageTitle => isEn ? 'Backup' : '备份';
  static String get restorePageTitle => isEn ? 'Restore Data' : '恢复数据';

  static String backupHeroTitle(bool restoreFirst) =>
      restoreFirst ? restorePageTitle : backupPageTitle;

  static String backupHeroSubtitle(bool restoreFirst) => restoreFirst
      ? (isEn
            ? 'Paste previously exported JSON to merge with current data or restore from snapshot.'
            : '把之前导出的 JSON 粘贴回来，可以合并到当前数据或覆盖本机数据。')
      : (isEn
            ? 'Package all local data into JSON text to copy, send, or back up to another device.'
            : '把本机所有数据打包成一段 JSON 文本，可以复制、发给自己，或者保存到另一台设备。');

  static String get backupSectionTitle => isEn ? 'Create Backup' : '生成备份';
  static String get backupSectionSubtitle =>
      isEn ? 'Export all local data as JSON' : '导出本机全部数据为 JSON';
  static String get generateJsonButton => isEn ? 'Generate JSON' : '生成 JSON';

  static String get restoreSectionTitle => isEn ? 'Restore Data' : '恢复数据';
  static String get restoreSectionSubtitle => isEn
      ? 'Paste backup JSON, or migrate todos, habits, notes, events, anniversaries, countdowns, and footprints from other apps via CSV / JSON'
      : '粘贴备份 JSON，或从其他 App 的 CSV / JSON 迁移待办、习惯、笔记、日程、纪念日、倒数日和时间足迹';

  static String get mergeImportButton => isEn ? 'Merge Import' : '合并导入';
  static String get overwriteImportButton => isEn ? 'Overwrite Import' : '覆盖导入';
  static String get fileMergeButton => isEn ? 'File Merge' : '文件合并';
  static String get fileOverwriteButton => isEn ? 'File Overwrite' : '文件覆盖';

  static String get importTasksFromOtherAppsButton =>
      isEn ? 'Import Todos from Other Apps' : '从其他 App 导入待办';
  static String get importProductivityFromOtherAppsButton =>
      isEn ? 'Import from Another App' : '从其他 App 导入数据';
  static String get importProductivityFileButton =>
      isEn ? 'Import Other App Data from File' : '从文件导入其他 App 数据';

  // --- 导入弹窗与语义提示 ---
  static String importDialogTitle(bool merge) => merge
      ? (isEn ? 'Merge Import' : '合并导入')
      : (isEn ? 'Overwrite Import' : '覆盖导入');

  static String get importDialogPasteHint => isEn
      ? 'Paste previously exported backup JSON here'
      : '把之前导出的备份 JSON 粘贴进来';

  static String importSuccess(bool merge, int count) => isEn
      ? 'Successfully ${merge ? 'merged' : 'imported'} $count items'
      : '成功${merge ? '合并' : '导入'} $count 项数据';

  static String importFileSuccess(bool merge, int count) => isEn
      ? 'Successfully ${merge ? 'merged' : 'imported'} $count items from file'
      : '已从文件${merge ? '合并' : '导入'} $count 项数据';

  static String get importFileOverwriteDialogTitle =>
      isEn ? 'Overwrite Import from File?' : '从文件覆盖导入?';

  static String get importFileOverwriteExplanation => isEn
      ? 'Select a backup file to restore. All local backupable data will be replaced with the snapshot.'
      : '会选择备份文件并覆盖本机可备份数据。';

  // --- 单模块导出 ---
  static String get singleModuleExportTitle =>
      isEn ? 'Single Module Export' : '单模块导出';
  static String get singleModuleExportSubtitle =>
      isEn ? 'CSV / Markdown format' : 'CSV / Markdown 格式';

  static String get exportChipTodoCsv => isEn ? 'Todos · CSV' : '待办 · CSV';
  static String get exportChipTodoMd =>
      isEn ? 'Todos · Markdown' : '待办 · Markdown';
  static String get exportChipHabitCsv => isEn ? 'Habits · CSV' : '习惯 · CSV';
  static String get exportChipTimeEntryCsv =>
      isEn ? 'Time Footprints · CSV' : '时间足迹 · CSV';
  static String get exportChipNoteCsv => isEn ? 'Notes · CSV' : '笔记 · CSV';
  static String get exportChipNoteMd =>
      isEn ? 'Notes · Markdown' : '笔记 · Markdown';
  static String get exportChipDiaryMd =>
      isEn ? 'Diary · Markdown' : '日记 · Markdown';
  static String get exportChipDiaryCsv => isEn ? 'Diary · CSV' : '日记 · CSV';
  static String get exportChipAnniversaryCsv =>
      isEn ? 'Anniversaries · CSV' : '纪念日 · CSV';
  static String get exportChipAnniversaryMd =>
      isEn ? 'Anniversaries · Markdown' : '纪念日 · Markdown';
  static String get exportChipGoalCsv => isEn ? 'Goals · CSV' : '目标 · CSV';
  static String get exportChipGoalMd =>
      isEn ? 'Goals · Markdown' : '目标 · Markdown';

  static String get exportTitleTodoCsv => isEn ? 'Todos CSV' : '待办 CSV';
  static String get exportTitleTodoMd =>
      isEn ? 'Todos Markdown' : '待办 Markdown';
  static String get exportTitleHabitCsv => isEn ? 'Habits CSV' : '习惯 CSV';
  static String get exportTitleTimeEntryCsv =>
      isEn ? 'Time Footprints CSV' : '时间足迹 CSV';
  static String get exportTitleNoteCsv => isEn ? 'Notes CSV' : '笔记 CSV';
  static String get exportTitleNoteMd =>
      isEn ? 'Notes Markdown' : '笔记 Markdown';
  static String get exportTitleDiaryMd =>
      isEn ? 'Diary Markdown' : '日记 Markdown';
  static String get exportTitleDiaryCsv => isEn ? 'Diary CSV' : '日记 CSV';
  static String get exportTitleAnniversaryCsv =>
      isEn ? 'Anniversaries CSV' : '纪念日 CSV';
  static String get exportTitleAnniversaryMd =>
      isEn ? 'Anniversaries Markdown' : '纪念日 Markdown';
  static String get exportTitleGoalCsv => isEn ? 'Goals CSV' : '目标 CSV';
  static String get exportTitleGoalMd =>
      isEn ? 'Goals Markdown' : '目标 Markdown';

  // --- 危险操作 ---
  static String get dangerZoneTitle => isEn ? 'Danger Zone' : '危险操作';
  static String get dangerZoneSubtitle => isEn
      ? 'Clearing local data permanently removes local records'
      : '清空本机数据会删除本地内容';
  static String get wipeButton => isEn ? 'Clear Local Data' : '清空本机数据';
  static String get wipeDialogTitle =>
      isEn ? 'Clear all local data?' : '清空全部数据?';
  static String get wipeDialogContent => isEn
      ? 'All local todos, habits, notes, diaries, etc. will be deleted. Logged-in accounts will remain unaffected.'
      : '将删除本机所有待办/习惯/笔记/日记等，登录账号不会删除。';
  static String get wipeSuccess => isEn ? 'Local data cleared' : '已清空本地数据';

  // --- WebDAV 云盘备份 ---
  static String get webDavSectionTitle =>
      isEn ? 'WebDAV Cloud Backup' : 'WebDAV 云盘备份';
  static String get webDavSubtitleNotConfigured => isEn
      ? 'Back up to OpenList, Jianguoyun, NAS, or other WebDAV-compatible cloud storage'
      : '备份到 OpenList、坚果云、NAS 等兼容 WebDAV 的云盘';

  static String webDavConfigureButton(bool configured) => configured
      ? (isEn ? 'Edit Settings' : '修改配置')
      : (isEn ? 'Configure WebDAV' : '配置云盘');

  static String get webDavUploadButton => isEn ? 'Upload Backup' : '上传备份';
  static String get webDavMergeButton => isEn ? 'Cloud Merge' : '云端合并';
  static String get webDavOverwriteButton => isEn ? 'Cloud Overwrite' : '云端覆盖';

  static String get webDavDialogTitle =>
      isEn ? 'WebDAV Cloud Backup' : 'WebDAV 云盘备份';
  static String get webDavUsername => isEn ? 'Username' : '用户名';
  static String get webDavPassword => isEn ? 'Password / Token' : '密码 / Token';
  static String get webDavRemotePath => isEn ? 'Remote Directory' : '远端目录';
  static String get webDavFilename => isEn ? 'Filename' : '文件名';
  static String get webDavConfigSaved =>
      isEn ? 'WebDAV settings saved' : 'WebDAV 配置已保存';

  static String webDavUploadSuccess(double kb, String uri) => isEn
      ? 'Uploaded to WebDAV: ${kb.toStringAsFixed(1)} KB · $uri'
      : '已上传到 WebDAV：${kb.toStringAsFixed(1)} KB · $uri';

  static String webDavRestoreDialogTitle(bool merge) => merge
      ? (isEn ? 'Merge restore from WebDAV?' : '从 WebDAV 合并恢复?')
      : (isEn ? 'Overwrite restore from WebDAV?' : '从 WebDAV 覆盖恢复?');

  static String webDavRestoreDesc(bool merge, String filename) => merge
      ? (isEn
            ? 'Will download $filename and merge with local data. Non-matching local records are preserved.'
            : '会下载 $filename 并合并到本机数据（保留未匹配的本机记录）。')
      : (isEn
            ? 'Will download $filename and restore to snapshot. Local data missing from the backup will be deleted.'
            : '会下载 $filename 并覆盖本机可备份数据。备份中不存在的本机数据将被删除。');

  static String webDavRestoreSuccess(bool merge, int count) => isEn
      ? 'Successfully ${merge ? 'merged' : 'restored'} $count items from WebDAV'
      : '已从 WebDAV ${merge ? '合并' : '恢复'} $count 项数据';

  // --- 第三方导入与字段映射 ---
  static String competitorImportDialogTitle(bool tasksOnly) => tasksOnly
      ? (isEn ? 'Import Todos from Other Apps' : '导入其他 App 待办')
      : (isEn ? 'Import Data from Other Apps' : '导入其他 App 数据');

  static String competitorImportPreviewAction(bool tasksOnly) => tasksOnly
      ? (isEn ? 'Preview Todos' : '预览待办')
      : (isEn ? 'Preview Data' : '预览数据');

  static String competitorImportPasteHint(bool tasksOnly) => tasksOnly
      ? (isEn
            ? 'Paste task export CSV / JSON from Todoist, TickTick, or Zhijian Time'
            : '粘贴 Todoist、滴答清单或指尖时光风格的 CSV / JSON 任务导出')
      : (isEn
            ? 'Paste CSV / JSON from Todoist, TickTick, or Zhijian Time; supports type=task/habit/note/event/birthday/anniversary/countdown/time_entry'
            : '粘贴 Todoist、滴答清单或指尖时光风格 CSV / JSON；支持 type=task/habit/note/event/birthday/anniversary/countdown/time_entry');

  static String get importCompetitorFileSourceTitle =>
      isEn ? 'Select File Source' : '选择文件来源';
  static String get importCompetitorFileSourceAction =>
      isEn ? 'Continue Preview' : '继续预览';

  static String get sourceLabel => isEn ? 'Source' : '来源';
  static String get sourceZhijianTime => isEn ? 'Zhijian Time' : '指尖时光';
  static String get sourceTickTick => isEn ? 'TickTick' : '滴答清单';
  static String get sourceTodoist => 'Todoist';
  static String get sourceGeneric =>
      isEn ? 'Generic CSV / JSON' : '通用 CSV / JSON';

  static String get hintZhijianTime => isEn
      ? 'Suitable for tasks, habits, notes, calendar events, birthdays, anniversaries, and countdowns exported from Zhijian Time.'
      : '适合指尖时光导出的计划、打卡、备忘录、日程、生日、纪念日和倒数日数据。';

  static String get hintTickTick => isEn
      ? 'Suitable for tasks, lists, tags, due dates, recurrences, and completion statuses exported from TickTick.'
      : '适合滴答清单导出的任务、清单、标签、截止时间、重复和完成状态。';

  static String get hintTodoist => isEn
      ? 'Suitable for tasks, projects, tags, priorities, due dates, and notes exported from Todoist.'
      : '适合 Todoist 导出的任务、项目、标签、优先级、截止日期和备注字段。';

  static String get hintGeneric => isEn
      ? 'Suitable for custom CSV / JSON. Use "type" field to specify task, habit, note, event, birthday, anniversary, countdown, or time_entry.'
      : '适合手工整理的 CSV / JSON。可用 type 字段指定 task、habit、note、event、birthday、anniversary、countdown、time_entry。';

  static String get advancedFieldMapping =>
      isEn ? 'Advanced Field Mapping' : '高级字段映射';
  static String get advancedFieldMappingHint => isEn
      ? 'Map non-standard export column names to Duoyi fields. Blank fields continue using automatic recognition.'
      : '把非标准导出字段映射到多仪字段。留空的字段继续使用自动识别。';
  static String get sourceFieldNameHint => isEn ? 'Source field name' : '来源字段名';
  static String standardFieldHelper(String target) =>
      isEn ? 'Standard field: $target' : '标准字段：$target';

  static String fieldTargetLabel(String key) {
    if (isEn) {
      return switch (key) {
        'title' => 'Title / Name',
        'date' => 'Date / Start Date',
        'due' => 'Due Time / End Date',
        'list' => 'List / Project',
        'tags' => 'Tags',
        'priority' => 'Priority',
        'quadrant' => 'Eisenhower Quadrant',
        'completed' => 'Completion Status',
        'completedAt' => 'Completed At',
        'reminder' => 'Reminder Time',
        'repeat' => 'Repeat Rule',
        'notes' => 'Notes / Description',
        'type' => 'Module Type',
        'target' => 'Habit Target Count',
        'unit' => 'Habit Unit',
        'category' => 'Category / Group',
        'duration' => 'Footprint Duration',
        _ => key,
      };
    }
    return switch (key) {
      'title' => '标题/名称',
      'date' => '日期/开始日期',
      'due' => '截止时间/结束时间',
      'list' => '清单/项目',
      'tags' => '标签',
      'priority' => '优先级',
      'quadrant' => '四象限',
      'completed' => '完成状态',
      'completedAt' => '完成时间',
      'reminder' => '提醒时间',
      'repeat' => '重复规则',
      'notes' => '备注/描述',
      'type' => '模块类型',
      'target' => '习惯目标次数',
      'unit' => '习惯单位',
      'category' => '分类/分组',
      'duration' => '时间足迹时长',
      _ => key,
    };
  }

  static String get fieldMappingNone =>
      isEn ? 'No field mapping set (using auto-detection)' : '未设置字段映射，使用自动识别';

  static String fieldMappingMoreItems(int count) =>
      isEn ? ', and $count more' : '，另 $count 项';

  // --- 预览与结果界面 ---
  static String get importPreviewTitle => isEn ? 'Import Preview' : '导入预览';
  static String importPreviewSource(String source, String format) =>
      isEn ? 'Source: $source · Format: $format' : '来源：$source · 格式：$format';
  static String importPreviewMapping(String summary) =>
      isEn ? 'Field mapping: $summary' : '字段映射：$summary';

  static String get moduleTodo => isEn ? 'Todos' : '待办';
  static String get moduleHabit => isEn ? 'Habits' : '习惯';
  static String get moduleNote => isEn ? 'Notes' : '笔记';
  static String get moduleEvent => isEn ? 'Calendar' : '日程';
  static String get moduleAnniversary => isEn ? 'Anniversaries' : '纪念日';
  static String get moduleCountdown => isEn ? 'Countdowns' : '倒数日';
  static String get moduleTimeEntry => isEn ? 'Footprints' : '时间足迹';
  static String get moduleSkippedRows => isEn ? 'Skipped Rows' : '解析跳过';

  static String tasksOnlyNotice(int count) => isEn
      ? 'Current entry only imports todos; $count other parsed module records will not be written.'
      : '当前入口只导入待办；解析出的 $count 条其它模块数据不会写入。';

  static String get duplicatePolicyNotice => isEn
      ? 'Duplicate handling: Deduplicates by existing title, date, and content. Duplicate items are skipped without overwriting local data.'
      : '重复项策略：导入时会按本机已有标题、日期、内容等字段自动去重；重复项会跳过，不覆盖本机数据。';

  static String get sampleHeader => isEn ? 'Samples' : '样例';
  static String get warningHeader => isEn ? 'Parsing Notes' : '解析提示';
  static String get confirmImportPolicyCheckbox => isEn
      ? 'I have confirmed the preview and duplicate handling policy'
      : '我已确认预览和重复项处理策略';

  static String get importCompletedTitle => isEn ? 'Import Complete' : '导入完成';
  static String itemCount(int count) => isEn ? '$count items' : '$count 项';
  static String skippedSummary(int invalid, int duplicates) => isEn
      ? 'Skipped: $invalid invalid, $duplicates duplicates'
      : '跳过：解析无效 $invalid，重复 $duplicates';
  static String get tasksOnlyResultNotice => isEn
      ? 'Using todo entry; other modules were previewed only and not saved.'
      : '本次使用待办入口，其它模块仅预览未写入。';
  static String get warningsPrefix => isEn ? 'Note: ' : '提示：';

  static String reminderNotFullyRegistered(String issues) =>
      isEn ? 'Reminders partially registered: $issues' : '提醒未完全注册：$issues';

  static String reminderMoreNeedResaving(int count) => isEn
      ? 'Another $count reminder categories need to be reopened and saved.'
      : '另有 $count 类提醒需要重新保存。';

  static String get rollbackHint => isEn
      ? 'If the import result does not match expectations, you can undo this import and restore the pre-import snapshot.'
      : '如发现导入结果不符合预期，可撤销本次导入并恢复到导入前的本地快照。';

  static String importSuccessBanner(
    String source,
    int inserted,
    int skipped,
    String reminderIssueSuffix,
  ) => isEn
      ? 'Imported $inserted items from $source, skipped $skipped items$reminderIssueSuffix'
      : '已从 $source 导入 $inserted 项，跳过 $skipped 项$reminderIssueSuffix';

  static String get partialRemindersSuffix => isEn
      ? '; some reminders not registered, please reopen and resave'
      : '；部分提醒未注册，请打开对应事项重新保存';

  static String noDataRecognized(bool tasksOnly, String warning) => isEn
      ? 'No importable ${tasksOnly ? 'todos' : 'data'} recognized$warning'
      : '未识别到可导入${tasksOnly ? '待办' : '数据'}$warning';

  // --- 主题与奖励商店界面 ---
  static String get themeSaveFailed =>
      isEn ? 'Failed to save theme settings' : '主题保存失败';
  static String get rewardShopReason =>
      isEn ? 'Reward shop theme decoration' : '奖励商店主题装饰';

  static String insufficientCoins(int diff) =>
      isEn ? 'Not enough Time Coins, need $diff more' : '时光币不足，还差 $diff';

  static String themeApplied(String name) =>
      isEn ? 'Applied $name' : '已启用 $name';
  static String themeRedeemedAndApplied(String name) =>
      isEn ? 'Redeemed and applied $name' : '已兑换并启用 $name';

  static String widgetBackgroundSwitched(String label) =>
      isEn ? 'Widget background switched to $label' : '小组件背景已切换为 $label';
  static String get unlockThemeFirst =>
      isEn ? 'Please unlock this theme first' : '请先解锁该主题';

  static String widgetCardSkinSwitched(String label) =>
      isEn ? 'Widget card skin switched to $label' : '小组件卡片皮肤已切换为 $label';
  static String get unlockCardSkinFirst =>
      isEn ? 'Please unlock this card skin first' : '请先解锁该卡片皮肤';

  static String get widgetFollowCurrentTheme =>
      isEn ? 'Follow Current Theme' : '跟随当前主题';
  static String get widgetFollowCardSkin =>
      isEn ? 'Follow Card Skin' : '跟随卡片皮肤';

  static String get widgetThemeTitle =>
      isEn ? 'Desktop Widget Theme' : '桌面小组件主题';
  static String get widgetThemeSubtitle => isEn
      ? 'Adjust desktop widget background and card skin individually'
      : '单独调整桌面小组件背景和卡片皮肤';
  static String get widgetBackgroundLabel => isEn ? 'Background' : '背景图';
  static String get widgetCardSkinLabel => isEn ? 'Card Skin' : '卡片皮肤';

  static String coinCount(int count) =>
      isEn ? 'Time Coins $count' : '时光币 $count';
  static String coinCost(int cost) => isEn ? '$cost Coins' : '$cost 币';

  static String get focusBackdropSectionTitle =>
      isEn ? 'Focus Backdrops' : '专注背景';
  static String get focusBackdropSectionSubtitle => isEn
      ? 'Redeem Pomodoro card decorations with Time Coins'
      : '用时光币兑换番茄钟卡片装饰';

  static String get avatarFrameSectionTitle => isEn ? 'Avatar Frames' : '头像框';
  static String get avatarFrameSectionSubtitle => isEn
      ? 'Redeem Profile avatar decorations with Time Coins'
      : '用时光币兑换我的页头像装饰';

  static String get cardSkinSectionTitle => isEn ? 'Card Skins' : '卡片皮肤';
  static String get cardSkinSectionSubtitle =>
      isEn ? 'Redeem information card styles with Time Coins' : '用时光币兑换信息卡片质感';

  static String get widgetSyncNoticeTitle => isEn ? 'Widget Theme' : '小组件主题';
  static String get widgetSyncNoticeSubtitle => isEn
      ? 'Background and card skin sync to device home widgets'
      : '背景图和卡片皮肤会同步到手机桌面小组件';

  // --- 内置奖励展示文案（按稳定 ID 匹配，未知时回退原生名称与描述） ---
  static String focusBackdropName(String id, String fallback) {
    if (isEn) {
      return switch (id) {
        'classic_focus' => 'Classic Focus',
        'morning_focus' => 'Morning Desk',
        'forest_focus' => 'Forest Breeze',
        'ocean_focus' => 'Ocean Flow',
        'night_focus' => 'Night Flight',
        _ => fallback,
      };
    }
    return fallback;
  }

  static String focusBackdropDescription(String id, String fallback) {
    if (isEn) {
      return switch (id) {
        'classic_focus' => 'Clean gradient Pomodoro background',
        'morning_focus' =>
          'Warm background ideal for morning study and reading',
        'forest_focus' => 'Natural green background for deep, sustained focus',
        'ocean_focus' =>
          'Calm cyan background for review and low-pressure focus',
        'night_focus' => 'Low-brightness dark background for night study',
        _ => fallback,
      };
    }
    return fallback;
  }

  static String avatarFrameName(String id, String fallback) {
    if (isEn) {
      return switch (id) {
        'simple_frame' => 'Simple Frame',
        'golden_frame' => 'Golden Medal Frame',
        'forest_frame' => 'Green Leaf Frame',
        'aurora_frame' => 'Aurora Energy Frame',
        _ => fallback,
      };
    }
    return fallback;
  }

  static String avatarFrameDescription(String id, String fallback) {
    if (isEn) {
      return switch (id) {
        'simple_frame' => 'Default avatar frame style',
        'golden_frame' => 'Golden frame for achievement masters',
        'forest_frame' => 'Natural leafy frame for consistent habit streaks',
        'aurora_frame' => 'Glowing aurora frame for productive weeks',
        _ => fallback,
      };
    }
    return fallback;
  }

  static String cardSkinName(String id, String fallback) {
    if (isEn) {
      return switch (id) {
        'plain_card' => 'Plain Card',
        'paper_card' => 'Paper Planner Card',
        'mint_card' => 'Mint Checklist Card',
        'starlight_card' => 'Starlight Glass Card',
        _ => fallback,
      };
    }
    return fallback;
  }

  static String cardSkinDescription(String id, String fallback) {
    if (isEn) {
      return switch (id) {
        'plain_card' => 'Default card surface style',
        'paper_card' => 'Gentle paper texture for schedules and todos',
        'mint_card' => 'Refreshing card style for habits and focus logs',
        'starlight_card' => 'Low-light glass texture for evening reviews',
        _ => fallback,
      };
    }
    return fallback;
  }

  // --- 错误提示格式化（严格遮蔽技术栈、堆栈与凭据） ---
  static String formatExportError(Object? error) {
    return _formatGenericError(
      error,
      defaultEn:
          'Export failed. Please check storage permissions and try again.',
      defaultZh: '导出失败，请检查存储权限后重试',
    );
  }

  static String formatImportError(Object? error) {
    if (error is FormatException) {
      return isEn
          ? 'Invalid JSON format. Please verify the backup content.'
          : '备份内容不是有效的 JSON 格式，请核对后重试';
    }
    return _formatGenericError(
      error,
      defaultEn: 'Import failed. Please check the backup content and retry.',
      defaultZh: '导入失败，请检查备份内容后重试',
    );
  }

  static String formatFileImportError(Object? error) {
    if (error is FormatException) {
      return isEn
          ? 'Selected file format is invalid. Please select a valid backup file.'
          : '所选文件格式无效，请核对备份文件';
    }
    return _formatGenericError(
      error,
      defaultEn: 'File import failed. Please check the file and try again.',
      defaultZh: '文件导入失败，请检查文件后重试',
    );
  }

  static String formatFileMigrationError(Object? error) {
    if (error is FormatException) {
      return isEn
          ? 'File format is not recognized. Please check source type and field mapping.'
          : '文件解析失败，请检查来源类型与字段映射';
    }
    return _formatGenericError(
      error,
      defaultEn: 'File migration failed. Please try again.',
      defaultZh: '文件迁移失败，请检查后重试',
    );
  }

  static String formatDataMigrationError(Object? error) {
    return _formatGenericError(
      error,
      defaultEn: 'Data migration failed. Please check source data and retry.',
      defaultZh: '数据迁移失败，请检查来源数据后重试',
    );
  }

  static String formatRollbackError(Object? error) {
    return _formatGenericError(
      error,
      defaultEn: 'Failed to undo import. Local data remains unchanged.',
      defaultZh: '撤销导入失败，本地数据未变更',
    );
  }

  static String formatWebDavSaveError(Object? error) {
    if (error is FormatException) {
      return isEn
          ? 'Please enter a valid WebDAV URL (e.g., https://dav.example.com/dav).'
          : '请输入有效的 WebDAV URL（如 https://dav.example.com/dav）';
    }
    return _formatGenericError(
      error,
      defaultEn: 'Failed to save WebDAV configuration. Please check the input.',
      defaultZh: '保存 WebDAV 配置失败，请检查输入项',
    );
  }

  static String formatWebDavUploadError(Object? error) {
    return _formatWebDavActionError(
      error,
      actionEn: 'upload backup to WebDAV',
      actionZh: 'WebDAV 备份上传',
    );
  }

  static String formatWebDavRestoreError(Object? error) {
    return _formatWebDavActionError(
      error,
      actionEn: 'restore from WebDAV',
      actionZh: 'WebDAV 恢复',
    );
  }

  static String _formatWebDavActionError(
    Object? error, {
    required String actionEn,
    required String actionZh,
  }) {
    if (error == null) {
      return isEn ? 'Operation failed, please try again.' : '操作未成功，请稍后重试';
    }
    if (error is FormatException) {
      return isEn ? 'Please enter a valid WebDAV URL.' : '请输入有效的 WebDAV URL';
    }
    if (error is SocketException ||
        error is TimeoutException ||
        error.toString().toLowerCase().contains('socket') ||
        error.toString().toLowerCase().contains('handshake') ||
        error.toString().toLowerCase().contains('connection refused') ||
        error.toString().toLowerCase().contains('timed out')) {
      return isEn
          ? 'Cannot connect to WebDAV server. Please check your network and server URL.'
          : '无法连接到 WebDAV 服务器，请检查网络和服务器地址';
    }

    final raw = error.toString().toLowerCase();
    if (raw.contains('401') || raw.contains('403')) {
      return isEn
          ? 'WebDAV authentication failed. Please verify your username and password/token.'
          : 'WebDAV 认证失败，请检查用户名和密码/Token';
    }
    if (raw.contains('404')) {
      return isEn
          ? 'Remote backup file not found on WebDAV server.'
          : 'WebDAV 云端未找到指定的备份文件';
    }
    if (raw.contains('http')) {
      return isEn
          ? 'WebDAV server returned an error. Please verify the URL and folder permissions.'
          : 'WebDAV 服务器返回错误，请检查路径与读写权限';
    }

    return isEn
        ? 'Failed to $actionEn. Please check your settings and network connection.'
        : '$actionZh失败，请检查配置与网络连接';
  }

  static String _formatGenericError(
    Object? error, {
    required String defaultEn,
    required String defaultZh,
  }) {
    if (error == null) {
      return isEn ? 'Operation failed, please try again.' : '操作未成功，请重试';
    }
    if (error is ApiException) {
      return userVisibleApiError(
        error,
        fallbackMessage: isEn ? defaultEn : defaultZh,
      );
    }
    return isEn ? defaultEn : defaultZh;
  }
}
