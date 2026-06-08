import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_update_installer.dart';
import '../services/app_update_service.dart';
import 'brand_background.dart';
import 'surface_components.dart';

class ForceUpdateGate extends StatefulWidget {
  const ForceUpdateGate({super.key});

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate> {
  final ScrollController _notesScrollController = ScrollController();

  @override
  void dispose() {
    _notesScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final updater = context.watch<AppUpdateService>();
    if (!updater.mustUpdate) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final notes = updater.latestNotesForDisplay;
    final canInstall =
        (updater.latestUrl != null || updater.hasDownloadedInstaller) &&
        AppUpdateInstaller.supportsInstall;

    return Positioned.fill(
      child: PopScope(
        canPop: false,
        child: Material(
          color: colorScheme.surface,
          child: BrandBackground(
            overlayOpacity: 0.46,
            child: ColoredBox(
              color:
                  (theme.brightness == Brightness.dark
                          ? Colors.black
                          : colorScheme.surface)
                      .withValues(
                        alpha: theme.brightness == Brightness.dark
                            ? 0.28
                            : 0.16,
                      ),
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.14,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.24,
                                  ),
                                ),
                              ),
                              child: Icon(
                                Icons.system_update_alt_outlined,
                                size: 34,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            '需要更新后才能继续使用',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '管理员已开启强制更新策略。更新完成前，应用功能会暂时锁定。',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          AppSurfaceCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ForceUpdateInfoRow(
                                  label: '当前版本',
                                  value: updater.currentVersion,
                                ),
                                _ForceUpdateInfoRow(
                                  label: '最新版本',
                                  value: updater.latestVersion ?? '未配置',
                                ),
                                if (updater.minimumSupportedVersion != null)
                                  _ForceUpdateInfoRow(
                                    label: '最低支持版本',
                                    value: updater.minimumSupportedVersion!,
                                  ),
                                if (updater.latestAssetName != null)
                                  _ForceUpdateInfoRow(
                                    label: '安装包',
                                    value: updater.latestAssetName!,
                                  ),
                              ],
                            ),
                          ),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              '更新内容',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 180),
                              child: AppSurfaceCard(
                                padding: const EdgeInsets.all(14),
                                child: Scrollbar(
                                  controller: _notesScrollController,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: _notesScrollController,
                                    child: SelectableText(
                                      notes,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (updater.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              updater.error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colorScheme.error),
                            ),
                          ],
                          if (updater.latestUrl == null &&
                              !updater.hasDownloadedInstaller) ...[
                            const SizedBox(height: 12),
                            AppInfoBanner(
                              icon: Icons.link_off_outlined,
                              title: '安装包暂不可用',
                              message:
                                  '管理员未配置下载地址，或发布通道还没有提供可安装的新版本。请等待发布包同步完成。',
                              color: colorScheme.error,
                              margin: EdgeInsets.zero,
                            ),
                          ] else if (!AppUpdateInstaller.supportsInstall) ...[
                            const SizedBox(height: 12),
                            AppInfoBanner(
                              icon: Icons.install_mobile_outlined,
                              title: '当前平台不支持应用内安装',
                              message: '请在 Android 手机上安装更新包；桌面或 Web 端仅展示更新说明。',
                              color: colorScheme.primary,
                              margin: EdgeInsets.zero,
                            ),
                          ],
                          if (updater.downloading) ...[
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value: updater.downloadProgress,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              updater.downloadProgress == null
                                  ? '正在下载更新包'
                                  : '正在下载 ${(updater.downloadProgress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ] else if (updater.installing) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                            const SizedBox(height: 6),
                            Text(
                              '正在打开安装器',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: canInstall && !updater.busy
                                ? () async {
                                    await updater.downloadAndInstallLatest();
                                  }
                                : null,
                            icon: const Icon(
                              Icons.download_for_offline_outlined,
                            ),
                            label: Text(
                              updater.hasDownloadedInstaller
                                  ? '安装已下载包'
                                  : '下载并安装',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ForceUpdateInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _ForceUpdateInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
