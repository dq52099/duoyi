import '../services/api_client.dart';
import 'i18n.dart';

/// App-owned update copy selected when it is rendered, not when an update is
/// checked. Literal notices are reserved for release notes and server-authored
/// policy reasons; rendering them never trims, translates, or formats them.
enum AppUpdateNoticeKind {
  literal,
  checkTitle,
  requiredTitle,
  requiredDescription,
  currentVersionLabel,
  latestVersionLabel,
  unconfiguredVersion,
  minimumVersionLabel,
  installerLabel,
  notesHeading,
  updateAvailable,
  upToDate,
  installerUnavailableTitle,
  installerUnavailableMessage,
  unsupportedPlatformTitle,
  unsupportedPlatformMessage,
  downloading,
  downloadProgress,
  openingInstaller,
  installDownloaded,
  downloadAndInstall,
  generatedReleaseNotes,
  notesSummaryHeading,
  releaseNotPublished,
  checkFailed,
  noDownloadableApk,
  installPermissionRequired,
  unsupportedInstallPlatform,
  downloadFailed,
}

/// Lazy-rendered app-owned updater copy.
///
/// Pass [locale] to freeze the rendering locale for a notification or exported
/// message. Use [AppUpdateNotice.literal] for externally authored release notes
/// and blocked reasons so their content stays byte-for-byte unchanged.
final class AppUpdateNotice {
  const AppUpdateNotice(this.kind, {this.error, this.version, this.progress})
    : literalText = null;

  const AppUpdateNotice.literal(String text)
    : kind = AppUpdateNoticeKind.literal,
      error = null,
      version = null,
      progress = null,
      literalText = text;

  final AppUpdateNoticeKind kind;
  final Object? error;
  final String? version;
  final double? progress;
  final String? literalText;

  String render({AppLocale? locale}) {
    final selected = locale ?? I18n.current;
    final isEn = selected == AppLocale.en;
    String pick(String zh, String en) => isEn ? en : zh;

    return switch (kind) {
      AppUpdateNoticeKind.literal => literalText ?? '',
      AppUpdateNoticeKind.checkTitle => pick('检查更新', 'Check for updates'),
      AppUpdateNoticeKind.requiredTitle => pick(
        '需要更新后才能继续使用',
        'Update required to continue',
      ),
      AppUpdateNoticeKind.requiredDescription => pick(
        '管理员已开启强制更新策略。更新完成前，应用功能会暂时锁定。',
        'An administrator requires this update. App features stay locked until it is installed.',
      ),
      AppUpdateNoticeKind.currentVersionLabel => pick(
        '当前版本',
        'Current version',
      ),
      AppUpdateNoticeKind.latestVersionLabel => pick('最新版本', 'Latest version'),
      AppUpdateNoticeKind.unconfiguredVersion => pick('未配置', 'Not configured'),
      AppUpdateNoticeKind.minimumVersionLabel => pick(
        '最低支持版本',
        'Minimum supported version',
      ),
      AppUpdateNoticeKind.installerLabel => pick('安装包', 'Installer'),
      AppUpdateNoticeKind.notesHeading => pick('更新内容', 'What’s new'),
      AppUpdateNoticeKind.updateAvailable => pick(
        '发现新版本',
        'New version available',
      ),
      AppUpdateNoticeKind.upToDate => pick('已是最新版本', 'You are up to date'),
      AppUpdateNoticeKind.installerUnavailableTitle => pick(
        '安装包暂不可用',
        'Installer unavailable',
      ),
      AppUpdateNoticeKind.installerUnavailableMessage => pick(
        '管理员未配置下载地址，或发布通道还没有提供可安装的新版本。请等待发布包同步完成。',
        'No download URL is configured, or the release channel does not have an installable package yet. Wait for the package to sync.',
      ),
      AppUpdateNoticeKind.unsupportedPlatformTitle => pick(
        '当前平台不支持应用内安装',
        'In-app installation is not supported on this platform',
      ),
      AppUpdateNoticeKind.unsupportedPlatformMessage => pick(
        '请在 Android 手机上安装更新包；桌面或 Web 端仅展示更新说明。',
        'Install the update package on an Android phone. Desktop and web only show update notes.',
      ),
      AppUpdateNoticeKind.downloading => pick('正在下载更新包', 'Downloading update'),
      AppUpdateNoticeKind.downloadProgress => pick(
        '正在下载 ${(progress ?? 0).clamp(0, 100).toStringAsFixed(0)}%',
        'Downloading ${(progress ?? 0).clamp(0, 100).toStringAsFixed(0)}%',
      ),
      AppUpdateNoticeKind.openingInstaller => pick(
        '正在打开安装器',
        'Opening installer',
      ),
      AppUpdateNoticeKind.installDownloaded => pick(
        '安装已下载包',
        'Install downloaded package',
      ),
      AppUpdateNoticeKind.downloadAndInstall => pick(
        '下载并安装',
        'Download and install',
      ),
      AppUpdateNoticeKind.generatedReleaseNotes => _generatedReleaseNotes(
        version,
        pick,
      ),
      AppUpdateNoticeKind.notesSummaryHeading => pick(
        '本次更新摘要：',
        'Update summary:',
      ),
      AppUpdateNoticeKind.releaseNotPublished => pick(
        '尚未发布 Release',
        'No release has been published yet.',
      ),
      AppUpdateNoticeKind.checkFailed => _renderCheckFailure(
        error,
        selected,
        pick,
      ),
      AppUpdateNoticeKind.noDownloadableApk => pick(
        '没有可下载的 APK',
        'No APK is available to download.',
      ),
      AppUpdateNoticeKind.installPermissionRequired => pick(
        '需要允许多仪安装未知应用；授权后返回这里再次点击安装',
        'Allow Duoyi to install unknown apps, then return here and tap Install again.',
      ),
      AppUpdateNoticeKind.unsupportedInstallPlatform => pick(
        '当前平台不支持应用内 APK 更新',
        'In-app APK updates are not supported on this platform.',
      ),
      AppUpdateNoticeKind.downloadFailed => _renderDownloadFailure(
        error,
        selected,
        pick,
      ),
    };
  }

  String _generatedReleaseNotes(
    String? version,
    String Function(String, String) pick,
  ) {
    final target = version?.trim();
    if (target == null || target.isEmpty) {
      return pick('未提供更新说明。', 'No release notes were provided.');
    }
    return pick(
      '版本 $target 未提供更新说明。',
      'No release notes were provided for version $target.',
    );
  }

  String _renderCheckFailure(
    Object? cause,
    AppLocale locale,
    String Function(String, String) pick,
  ) {
    final fallback = pick(
      '服务暂不可用，请稍后重试或联系管理员',
      'Service unavailable. Please try again later or contact an administrator.',
    );
    if (cause == null) return fallback;
    return userVisibleApiError(
      cause,
      fallbackMessage: fallback,
      locale: locale,
    );
  }

  String _renderDownloadFailure(
    Object? cause,
    AppLocale locale,
    String Function(String, String) pick,
  ) {
    final fallback = pick(
      '未能完成更新，请稍后重试。',
      'Could not complete the update. Please try again.',
    );
    if (cause == null) return fallback;
    final detail = userVisibleApiError(
      cause,
      fallbackMessage: fallback,
      locale: locale,
    );
    if (detail == fallback) return detail;
    return pick('更新失败：$detail', 'Update failed: $detail');
  }
}
