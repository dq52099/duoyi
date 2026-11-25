import 'i18n.dart';

abstract final class NoteEditorUiCopy {
  static bool get _en => I18n.current == AppLocale.en;
  static String get saving => _en ? 'Saving…' : '正在保存…';
  static String get saveFailed => _en
      ? 'Could not save note. Your draft is still here. Try again.'
      : '保存失败，草稿已保留，请重试';
  static String get attachmentFailed =>
      _en ? 'Could not add attachment. Try again.' : '添加附件失败，请重试';
  static String get openFailed => _en
      ? 'Could not open attachment. Check that the file or link is available.'
      : '无法打开附件，请检查文件或链接是否可用';
  static String get choosingAttachment =>
      _en ? 'Choosing an attachment' : '正在选择附件';
  static String get requiredLocation =>
      _en ? 'Enter a link or local path' : '请填写链接或本地路径';
  static String get expired => _en
      ? 'Page state changed. Return and reopen this note.'
      : '页面状态已变更，请返回后重新打开便签';
  static String get back => _en ? 'Back to notes' : '返回便签列表';
}
