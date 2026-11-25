import 'i18n.dart';

/// Fixed audit UI labels. Server actors, targets and details stay unchanged.
class AdminAuditUiCopy {
  static String _text(String zh, String en, AppLocale? locale) =>
      (locale ?? I18n.current) == AppLocale.en ? en : zh;

  static String titleFor([AppLocale? locale]) =>
      _text('审计日志', 'Audit log', locale);
  static String searchHintFor([AppLocale? locale]) => _text(
    '搜索管理员、操作、对象或详情',
    'Search administrators, actions, targets or details',
    locale,
  );
  static String clearSearchFor([AppLocale? locale]) =>
      _text('清空日志搜索', 'Clear audit search', locale);
  static String sortTitleFor([AppLocale? locale]) =>
      _text('日志排序', 'Sort audit log', locale);
  static String loadingFor([AppLocale? locale]) =>
      _text('正在加载审计日志…', 'Loading audit log…', locale);
  static String updatingFor([AppLocale? locale]) =>
      _text('正在更新审计日志', 'Updating audit log', locale);
  static String emptyFor([AppLocale? locale]) =>
      _text('暂无操作记录', 'No activity recorded yet.', locale);
  static String noMatchesFor([AppLocale? locale]) => _text(
    '没有匹配的操作记录，请调整筛选条件',
    'No matching activity. Adjust your filters.',
    locale,
  );

  static String sortLabel(String value, [AppLocale? locale]) => switch (value) {
    'actor_asc' => _text('管理员 A-Z', 'Administrator A–Z', locale),
    'action_asc' => _text('操作类型 A-Z', 'Action A–Z', locale),
    'target_asc' => _text('对象 A-Z', 'Target A–Z', locale),
    _ => _text('最新操作优先', 'Newest activity first', locale),
  };

  static String actionLabel(String value, [AppLocale? locale]) =>
      switch (value) {
        '' => _text('全部操作', 'All actions', locale),
        'user.update' => _text('更新用户', 'Update user', locale),
        'user.delete' => _text('删除用户', 'Delete user', locale),
        'announcement.create' => _text('创建公告', 'Create announcement', locale),
        'announcement.update' => _text('更新公告', 'Update announcement', locale),
        'announcement.delete' => _text('删除公告', 'Delete announcement', locale),
        'feedback.reply' => _text('回复反馈', 'Reply to feedback', locale),
        'feedback.delete' => _text('删除反馈', 'Delete feedback', locale),
        'feedback.bulk_status' => _text(
          '批量处理反馈',
          'Update feedback in bulk',
          locale,
        ),
        'feedback.export' => _text('导出反馈', 'Export feedback', locale),
        'invite.create' => _text('生成邀请码', 'Create invite codes', locale),
        'invite.delete' => _text('删除邀请码', 'Delete invite code', locale),
        _ => value,
      };

  static String actor(String value, [AppLocale? locale]) =>
      _text('管理员：$value', 'Administrator: $value', locale);
  static String target(String value, [AppLocale? locale]) =>
      _text('对象：$value', 'Target: $value', locale);
  static String detail(String value, [AppLocale? locale]) =>
      _text('详情：$value', 'Details: $value', locale);
  static String pageSize(int value, [AppLocale? locale]) =>
      _text('每页：$value', 'Per page: $value', locale);
  static String pageNumber(int current, int total, [AppLocale? locale]) =>
      _text('页码：$current/$total', 'Page: $current/$total', locale);
}
