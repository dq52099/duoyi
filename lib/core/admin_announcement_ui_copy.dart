import 'i18n.dart';

/// Interface copy only; announcement titles, bodies and unknown levels are data.
class AdminAnnouncementUiCopy {
  AdminAnnouncementUiCopy._();

  static String _text(AppLocale? locale, String zh, String en) =>
      (locale ?? I18n.current) == AppLocale.zh ? zh : en;

  static String listTitleFor([AppLocale? locale]) =>
      _text(locale, '公告列表', 'Announcements');
  static String newTitleFor([AppLocale? locale]) =>
      _text(locale, '新增公告', 'New announcement');
  static String editTitleFor([AppLocale? locale]) =>
      _text(locale, '编辑公告', 'Edit announcement');
  static String editFor([AppLocale? locale]) => _text(locale, '编辑', 'Edit');
  static String searchHintFor([AppLocale? locale]) =>
      _text(locale, '搜索公告标题或正文', 'Search titles or content');
  static String clearSearchFor([AppLocale? locale]) =>
      _text(locale, '清空公告搜索', 'Clear announcement search');
  static String allStatusesFor([AppLocale? locale]) =>
      _text(locale, '全部状态', 'All statuses');
  static String publishedFor([AppLocale? locale]) =>
      _text(locale, '已发布', 'Published');
  static String draftFor([AppLocale? locale]) => _text(locale, '草稿', 'Draft');
  static String allLevelsFor([AppLocale? locale]) =>
      _text(locale, '全部级别', 'All levels');
  static String sortTitleFor([AppLocale? locale]) =>
      _text(locale, '公告排序', 'Sort announcements');
  static String levelLabel(String level, [AppLocale? locale]) =>
      switch (level) {
        'info' => _text(locale, '普通', 'Info'),
        'warning' => _text(locale, '重要', 'Important'),
        'critical' => _text(locale, '紧急', 'Urgent'),
        _ => level,
      };
  static String sortLabel(String sort, [AppLocale? locale]) => switch (sort) {
    'updated_desc' => _text(locale, '最近更新优先', 'Recently updated'),
    'title_asc' => _text(locale, '标题 A-Z', 'Title A–Z'),
    'level_desc' => _text(locale, '紧急程度优先', 'Urgency'),
    _ => _text(locale, '最新创建优先', 'Newest first'),
  };
  static String loadingFor([AppLocale? locale]) =>
      _text(locale, '正在加载公告列表…', 'Loading announcements…');
  static String updatingFor([AppLocale? locale]) =>
      _text(locale, '正在更新公告列表', 'Updating announcements');
  static String emptyFor([AppLocale? locale]) => _text(
    locale,
    '暂无公告，可新增公告向用户分享消息',
    'No announcements yet. Create one to share an update.',
  );
  static String noMatchesFor([AppLocale? locale]) => _text(
    locale,
    '没有匹配的公告，请调整筛选条件',
    'No matching announcements. Try changing the filters.',
  );
  static String titleLabelFor([AppLocale? locale]) =>
      _text(locale, '标题', 'Title');
  static String bodyLabelFor([AppLocale? locale]) =>
      _text(locale, '正文', 'Content');
  static String levelLabelFor([AppLocale? locale]) =>
      _text(locale, '级别', 'Level');
  static String publishNowFor([AppLocale? locale]) =>
      _text(locale, '立即发布', 'Publish now');
  static String publishHelperFor([AppLocale? locale]) => _text(
    locale,
    '关闭后保存为草稿；只有发布的公告对用户可见',
    'Turn off to save a draft. Only published announcements are visible to users.',
  );
  static String titleRequiredFor([AppLocale? locale]) =>
      _text(locale, '请输入公告标题', 'Enter an announcement title');
  static String bodyRequiredFor([AppLocale? locale]) =>
      _text(locale, '请输入公告正文', 'Enter announcement content');
  static String createdAt(String value, [AppLocale? locale]) =>
      _text(locale, '创建：$value', 'Created: $value');
  static String updatedAt(String value, [AppLocale? locale]) =>
      _text(locale, '更新：$value', 'Updated: $value');
  static String menuTooltipFor([AppLocale? locale]) =>
      _text(locale, '公告操作', 'Announcement actions');
  static String publishFor([AppLocale? locale]) =>
      _text(locale, '发布', 'Publish');
  static String unpublishFor([AppLocale? locale]) =>
      _text(locale, '下架', 'Unpublish');
  static String deleteTitleFor([AppLocale? locale]) =>
      _text(locale, '删除公告？', 'Delete announcement?');
  static String deleteBody(String title, [AppLocale? locale]) => _text(
    locale,
    '将删除“$title”，用户将无法再看到这条公告，删除后无法恢复。',
    '“$title” will be permanently deleted and will no longer be visible to users.',
  );
  static String savedFor([AppLocale? locale]) =>
      _text(locale, '公告已保存', 'Announcement saved');
  static String publishedSuccessFor([AppLocale? locale]) =>
      _text(locale, '公告已发布', 'Announcement published');
  static String unpublishedSuccessFor([AppLocale? locale]) => _text(
    locale,
    '公告已下架并保留为草稿',
    'Announcement unpublished and kept as a draft',
  );
  static String deletedFor([AppLocale? locale]) =>
      _text(locale, '公告已删除', 'Announcement deleted');
  static String refreshFailed(String success, [AppLocale? locale]) => _text(
    locale,
    '$success，但列表刷新失败，请重试刷新',
    '$success, but the list could not refresh. Try refreshing again.',
  );
  static String listTargetFor([AppLocale? locale]) =>
      _text(locale, '公告列表', 'announcements');
  static String saveActionFor([AppLocale? locale]) =>
      _text(locale, '保存公告', 'save announcement');
  static String publishActionFor([AppLocale? locale]) =>
      _text(locale, '发布公告', 'publish announcement');
  static String unpublishActionFor([AppLocale? locale]) =>
      _text(locale, '下架公告', 'unpublish announcement');
  static String deleteActionFor([AppLocale? locale]) =>
      _text(locale, '删除公告', 'delete announcement');
}
