import 'i18n.dart';

/// Fixed Admin Feedback copy. Server records and persisted reply text stay data.
class AdminFeedbackUiCopy {
  AdminFeedbackUiCopy._();

  static String _text(String zh, String en, AppLocale? locale) =>
      (locale ?? I18n.current) == AppLocale.zh ? zh : en;

  static String titleFor([AppLocale? locale]) =>
      _text('反馈列表', 'Feedback', locale);
  static String searchHintFor([AppLocale? locale]) =>
      _text('搜索反馈内容、回复或用户名', 'Search feedback, replies or usernames', locale);
  static String clearSearchFor([AppLocale? locale]) =>
      _text('清空反馈搜索', 'Clear feedback search', locale);
  static String sortTitleFor([AppLocale? locale]) =>
      _text('反馈排序', 'Sort feedback', locale);
  static String loadingFor([AppLocale? locale]) =>
      _text('正在加载反馈列表…', 'Loading feedback…', locale);
  static String updatingFor([AppLocale? locale]) =>
      _text('正在更新反馈列表', 'Updating feedback', locale);
  static String emptyFor([AppLocale? locale]) =>
      _text('暂无反馈', 'No feedback yet.', locale);
  static String noMatchesFor([AppLocale? locale]) => _text(
    '没有匹配的反馈，请调整筛选条件',
    'No matching feedback. Adjust your filters.',
    locale,
  );
  static String allStatusesFor([AppLocale? locale]) =>
      _text('全部', 'All statuses', locale);
  static String detailTitleFor([AppLocale? locale]) =>
      _text('反馈详情', 'Feedback details', locale);
  static String detailTooltipFor([AppLocale? locale]) =>
      _text('查看反馈详情', 'View feedback details', locale);
  static String replyTitleFor([AppLocale? locale]) =>
      _text('回复反馈', 'Reply to feedback', locale);
  static String replyFor([AppLocale? locale]) => _text('回复', 'Reply', locale);
  static String replyFieldFor([AppLocale? locale]) =>
      _text('回复内容', 'Reply', locale);
  static String statusFieldFor([AppLocale? locale]) =>
      _text('处理状态', 'Status', locale);
  static String submitFor([AppLocale? locale]) => _text('提交', 'Submit', locale);
  static String expiredTitleFor([AppLocale? locale]) =>
      _text('操作已失效', 'Action expired', locale);
  static String expiredBodyFor([AppLocale? locale]) => _text(
    '账号、权限或页面已变更。请关闭后重新操作。',
    'Your account, access or page changed. Close and try again.',
    locale,
  );
  static String userFor([AppLocale? locale]) => _text('用户', 'User', locale);
  static String accountFor([AppLocale? locale]) =>
      _text('账号', 'Account', locale);
  static String categoryFor([AppLocale? locale]) =>
      _text('分类', 'Category', locale);
  static String statusFor([AppLocale? locale]) => _text('状态', 'Status', locale);
  static String createdFor([AppLocale? locale]) =>
      _text('提交', 'Submitted', locale);
  static String updatedFor([AppLocale? locale]) =>
      _text('更新', 'Updated', locale);
  static String contentFor([AppLocale? locale]) =>
      _text('内容', 'Content', locale);
  static String adminReplyFor([AppLocale? locale]) =>
      _text('管理员回复', 'Admin reply', locale);
  static String anonymousFor([AppLocale? locale]) =>
      _text('匿名用户', 'Anonymous user', locale);
  static String detailFailure(String error, [AppLocale? locale]) => _text(
    '详情加载失败，已展示列表摘要：$error',
    'Could not load details. Showing the list summary: $error',
    locale,
  );
  static String email(String email, bool verified, [AppLocale? locale]) =>
      '$email (${verified ? _text('已验证', 'verified', locale) : _text('未验证', 'unverified', locale)})';
  static bool isEmailVerified(Object? value) => value == true || value == 1;
  static String replyPreview(String value, [AppLocale? locale]) =>
      _text('回复: $value', 'Reply: $value', locale);

  static String categoryLabel(String value, [AppLocale? locale]) =>
      switch (value) {
        '' => _text('全部分类', 'All categories', locale),
        'feature' => _text('功能建议', 'Feature request', locale),
        'bug' => _text('问题反馈', 'Bug report', locale),
        'wish' => _text('愿望清单', 'Wish', locale),
        'other' => _text('其他', 'Other', locale),
        _ => value,
      };
  static String statusLabel(String value, [AppLocale? locale]) =>
      switch (value) {
        'open' => _text('待处理', 'Open', locale),
        'in_progress' => _text('处理中', 'In progress', locale),
        'resolved' => _text('已解决', 'Resolved', locale),
        'closed' => _text('已关闭', 'Closed', locale),
        _ => value,
      };
  static String sortLabel(String value, [AppLocale? locale]) => switch (value) {
    'created_desc' => _text('最新反馈优先', 'Newest feedback first', locale),
    'updated_desc' => _text('最近处理优先', 'Recently updated first', locale),
    'status_asc' => _text('待处理优先', 'Open feedback first', locale),
    'user_asc' => _text('用户 A-Z', 'User A–Z', locale),
    _ => value,
  };

  static String deleteTitleFor([AppLocale? locale]) =>
      _text('删除反馈？', 'Delete feedback?', locale);
  static String deleteMessage(String user, [AppLocale? locale]) => _text(
    '将删除 $user 的这条反馈，删除后无法恢复。',
    'Delete this feedback from $user? This cannot be undone.',
    locale,
  );
  static String closeTitleFor([AppLocale? locale]) =>
      _text('关闭反馈？', 'Close feedback?', locale);
  static String closeMessage(String user, [AppLocale? locale]) => _text(
    '将把 $user 的这条反馈标记为已关闭。',
    'Mark this feedback from $user as closed?',
    locale,
  );
  static String repliedFor([AppLocale? locale]) =>
      _text('反馈已回复', 'Reply saved', locale);
  static String closedFor([AppLocale? locale]) =>
      _text('反馈已关闭', 'Feedback closed', locale);
  static String deletedFor([AppLocale? locale]) =>
      _text('反馈已删除', 'Feedback deleted', locale);
  static String refreshFailed(String success, [AppLocale? locale]) => _text(
    '$success，但列表刷新失败，请刷新后查看。',
    '$success. The list could not refresh. Refresh to see the result.',
    locale,
  );
  static String bulkLimitFor([AppLocale? locale]) => _text(
    '每次最多处理 100 条，请将每页条数调至 100 或更少后再操作。',
    'Process up to 100 items at a time. Set the page size to 100 or fewer.',
    locale,
  );
  static String bulkLabel(String from, String to, [AppLocale? locale]) => _text(
    '本页${statusLabel(from, locale)}转${statusLabel(to, locale)}',
    'This page: ${statusLabel(from, locale)} → ${statusLabel(to, locale)}',
    locale,
  );
  static String bulkTitleFor([AppLocale? locale]) =>
      _text('批量处理反馈？', 'Update this page’s feedback?', locale);
  static String bulkMessage(int count, String to, [AppLocale? locale]) => _text(
    '将本页 $count 条反馈标记为${statusLabel(to, locale)}。',
    'Mark $count items on this page as ${statusLabel(to, locale)}?',
    locale,
  );
  static String bulkSaved(int count, String to, [AppLocale? locale]) => _text(
    '已将本页 $count 条反馈标记为${statusLabel(to, locale)}',
    '$count items marked as ${statusLabel(to, locale)}',
    locale,
  );
  static String summary(
    int count,
    Map<String, int> statuses, [
    AppLocale? locale,
  ]) => _text(
    '本页 $count 条 · 待处理 ${statuses['open'] ?? 0} · 处理中 ${statuses['in_progress'] ?? 0} · 已解决 ${statuses['resolved'] ?? 0}',
    'This page: $count · Open ${statuses['open'] ?? 0} · In progress ${statuses['in_progress'] ?? 0} · Resolved ${statuses['resolved'] ?? 0}',
    locale,
  );
  static String summaryHint(
    int total,
    String sort, [
    AppLocale? locale,
  ]) => _text(
    '共 $total 条反馈，按${sortLabel(sort, locale)}排列。导出当前筛选结果的前 5000 条。',
    '$total items, sorted by ${sortLabel(sort, locale)}. Export the first 5,000 matching items.',
    locale,
  );
  static String exportFor([AppLocale? locale]) =>
      _text('导出筛选结果', 'Export filtered results', locale);
  static String exportShareTextFor([AppLocale? locale]) =>
      _text('多仪管理员反馈导出', 'Duoyi admin feedback export', locale);
  static String exportSubjectFor([AppLocale? locale]) =>
      _text('多仪反馈 CSV', 'Duoyi feedback CSV', locale);
  static String exported(String path, [AppLocale? locale]) => _text(
    '反馈 CSV 已导出，路径已复制：$path',
    'Feedback CSV exported. Path copied: $path',
    locale,
  );
}
