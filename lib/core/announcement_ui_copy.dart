import 'i18n.dart';
import '../services/api_client.dart';

/// App-owned labels only. Published announcement content stays as authored.
class AnnouncementUiCopy {
  AnnouncementUiCopy._();

  static bool get _isEn => I18n.current == AppLocale.en;

  static String get loading => _isEn ? 'Loading announcements…' : '正在加载公告…';
  static String get updating => _isEn ? 'Updating announcements…' : '正在刷新公告…';
  static String get accountChanging => _isEn
      ? 'Announcements will load when the account is ready.'
      : '账号准备就绪后将加载公告。';
  static String get loadFailed =>
      _isEn ? 'Could not load announcements. Try again.' : '公告加载失败，请重试';
  static String get refreshFailed => _isEn
      ? 'Could not refresh. Showing the previously loaded announcements.'
      : '刷新未完成，仍显示上次加载的公告。';
  static String get retry => I18n.tr('action.retry');
  static String get refresh => I18n.tr('announcement.refresh');

  static String errorMessage(Object error, {bool hasItems = false}) {
    final safe = userVisibleApiError(error, fallbackMessage: loadFailed);
    if (!hasItems) return safe;
    return safe == loadFailed ? refreshFailed : '$refreshFailed\n$safe';
  }
}
