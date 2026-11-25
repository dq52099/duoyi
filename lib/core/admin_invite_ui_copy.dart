import 'i18n.dart';

/// Interface text only; codes, notes and account names remain supplied data.
class AdminInviteUiCopy {
  AdminInviteUiCopy._();

  static String _text(AppLocale? locale, String zh, String en) =>
      (locale ?? I18n.current) == AppLocale.zh ? zh : en;

  static String listTitleFor([AppLocale? locale]) =>
      _text(locale, '邀请码列表', 'Invite codes');
  static String generateTitleFor([AppLocale? locale]) =>
      _text(locale, '生成邀请码', 'Generate invite codes');
  static String generateFor([AppLocale? locale]) =>
      _text(locale, '生成', 'Generate');
  static String quantityFor([AppLocale? locale]) =>
      _text(locale, '数量', 'Quantity');
  static String noteFor([AppLocale? locale]) =>
      _text(locale, '备注（可选）', 'Note (optional)');
  static String searchHintFor([AppLocale? locale]) =>
      _text(locale, '搜索邀请码、备注或使用者', 'Search codes, notes or users');
  static String clearSearchFor([AppLocale? locale]) =>
      _text(locale, '清空邀请码搜索', 'Clear invite code search');
  static String allFor([AppLocale? locale]) =>
      _text(locale, '全部邀请码', 'All invite codes');
  static String unusedFor([AppLocale? locale]) =>
      _text(locale, '未使用', 'Unused');
  static String usedFor([AppLocale? locale]) => _text(locale, '已使用', 'Used');
  static String sortTitleFor([AppLocale? locale]) =>
      _text(locale, '邀请码排序', 'Sort invite codes');
  static String sortLabel(String sort, [AppLocale? locale]) => switch (sort) {
    'used_desc' => _text(locale, '最近使用优先', 'Recently used'),
    'code_asc' => _text(locale, '邀请码 A-Z', 'Code A–Z'),
    'note_asc' => _text(locale, '备注 A-Z', 'Note A–Z'),
    _ => _text(locale, '最新生成优先', 'Newest first'),
  };
  static String loadingFor([AppLocale? locale]) =>
      _text(locale, '正在加载邀请码列表…', 'Loading invite codes…');
  static String updatingFor([AppLocale? locale]) =>
      _text(locale, '正在更新邀请码列表', 'Updating invite codes');
  static String emptyFor([AppLocale? locale]) => _text(
    locale,
    '暂无邀请码，可生成邀请码供新用户注册',
    'No invite codes yet. Generate codes for new users.',
  );
  static String noMatchesFor([AppLocale? locale]) => _text(
    locale,
    '没有匹配的邀请码，请调整筛选条件',
    'No matching invite codes. Try changing the filters.',
  );
  static String createdAt(String value, [AppLocale? locale]) =>
      _text(locale, '创建：$value', 'Created: $value');
  static String usedAt(String value, [AppLocale? locale]) =>
      _text(locale, '使用：$value', 'Used: $value');
  static String usedBy(String name, [AppLocale? locale]) =>
      _text(locale, '使用者：$name', 'Used by: $name');
  static String generatedTitle(int count, [AppLocale? locale]) =>
      _text(locale, '已生成 $count 个邀请码', '$count invite codes generated');
  static String copyAndCloseFor([AppLocale? locale]) =>
      _text(locale, '复制并关闭', 'Copy and close');
  static String refreshFailedFor([AppLocale? locale]) => _text(
    locale,
    '邀请码已生成，但列表刷新失败。请保存这些邀请码，再刷新列表。',
    'The codes were generated, but the list could not refresh. Save these codes, then refresh the list.',
  );
  static String noCodesReturnedFor([AppLocale? locale]) => _text(
    locale,
    '请求已完成，但未收到邀请码。请先刷新列表，确认后再尝试生成。',
    'No codes were returned. Refresh the list and check it before generating again.',
  );
  static String deleteTitleFor([AppLocale? locale]) =>
      _text(locale, '删除邀请码？', 'Delete invite code?');
  static String deleteTooltipFor([AppLocale? locale]) =>
      _text(locale, '删除邀请码', 'Delete invite code');
  static String deleteBody(String code, [AppLocale? locale]) => _text(
    locale,
    '将删除未使用的邀请码 $code，删除后无法恢复。',
    'The unused invite code $code will be permanently deleted.',
  );
  static String deletedFor([AppLocale? locale]) =>
      _text(locale, '邀请码已删除', 'Invite code deleted');
  static String deleteRefreshFailedFor([AppLocale? locale]) => _text(
    locale,
    '邀请码已删除，但列表刷新失败，请重试刷新',
    'The invite code was deleted, but the list could not refresh. Try refreshing again.',
  );
  static String listTargetFor([AppLocale? locale]) =>
      _text(locale, '邀请码列表', 'invite codes');
  static String generateActionFor([AppLocale? locale]) =>
      _text(locale, '生成邀请码', 'generate invite codes');
  static String deleteActionFor([AppLocale? locale]) =>
      _text(locale, '删除邀请码', 'delete invite code');
  static String copyActionFor([AppLocale? locale]) =>
      _text(locale, '复制邀请码', 'copy invite codes');
}
