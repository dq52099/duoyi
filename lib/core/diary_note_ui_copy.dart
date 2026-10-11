import 'i18n.dart';

/// Generated record titles. Authored content never passes through this helper.
class DiaryNoteUiCopy {
  const DiaryNoteUiCopy(this.locale);

  final AppLocale locale;

  String diaryTitle(DateTime date) => locale == AppLocale.en
      ? 'Diary for ${date.month}/${date.day}'
      : '${date.month}月${date.day}日的日记';

  String get untitledNote => locale == AppLocale.en ? 'Untitled note' : '无标题笔记';
}
