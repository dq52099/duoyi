typedef AppUpdateProgress = void Function(int receivedBytes, int? totalBytes);

class AppUpdateInstaller {
  static const bool supportsInstall = false;

  static Future<String> downloadApk({
    required String url,
    required String fileName,
    required AppUpdateProgress onProgress,
  }) {
    throw UnsupportedError('当前平台不支持应用内下载更新');
  }

  static Future<bool> canInstallPackages() async => false;

  static Future<void> openInstallPermissionSettings() async {}

  static Future<bool> downloadedFileExists(String path) async => false;

  static Future<void> installApk(String path) {
    throw UnsupportedError('当前平台不支持应用内安装 APK');
  }
}
