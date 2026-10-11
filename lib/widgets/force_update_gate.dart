import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_update_ui_copy.dart';
import '../core/i18n.dart';
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
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
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
                            AppUpdateUiCopy.requiredTitle(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppUpdateUiCopy.requiredDescription(),
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
                                  label: AppUpdateUiCopy.currentVersionLabel(),
                                  value: updater.currentVersion,
                                ),
                                _ForceUpdateInfoRow(
                                  label: AppUpdateUiCopy.latestVersionLabel(),
                                  value: updater.latestVersion ??
                                      AppUpdateUiCopy.unconfiguredVersion(),
                                ),
                                if (updater.minimumSupportedVersion != null)
                                  _ForceUpdateInfoRow(
                                    label:
                                        AppUpdateUiCopy.minimumVersionLabel(),
                                    value: updater.minimumSupportedVersion!,
                                  ),
                                if (updater.latestAssetName != null)
                                  _ForceUpdateInfoRow(
                                    label: AppUpdateUiCopy.installerLabel(),
                                    value: updater.latestAssetName!,
                                  ),
                              ],
                            ),
                          ),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              AppUpdateUiCopy.notesHeading(),
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
                              title: AppUpdateUiCopy.installerUnavailableTitle(),
                              message:
                                  AppUpdateUiCopy.installerUnavailableMessage(),
                              color: colorScheme.error,
                              margin: EdgeInsets.zero,
                            ),
                          ] else if (!AppUpdateInstaller.supportsInstall) ...[
                            const SizedBox(height: 12),
                            AppInfoBanner(
                              icon: Icons.install_mobile_outlined,
                              title: AppUpdateUiCopy.unsupportedPlatformTitle(),
                              message:
                                  AppUpdateUiCopy.unsupportedPlatformMessage(),
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
                                  ? AppUpdateUiCopy.downloading()
                                  : AppUpdateUiCopy.downloadProgress(
                                      updater.downloadProgress! * 100,
                                    ),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ] else if (updater.installing) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                            const SizedBox(height: 6),
                            Text(
                              AppUpdateUiCopy.openingInstaller(),
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
                                  ? AppUpdateUiCopy.installDownloaded()
                                  : AppUpdateUiCopy.downloadAndInstall(),
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
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.normal,
    );
    final labelText = Text(label, style: labelStyle);
    final valueText = Text(
      _breakableUpdateValue(value),
      softWrap: true,
      style: valueStyle,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 300) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 2), valueText],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 96, child: labelText),
              Expanded(child: valueText),
            ],
          );
        },
      ),
    );
  }
}

String _breakableUpdateValue(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 24) return trimmed;
  final buffer = StringBuffer();
  var runLength = 0;
  for (final codePoint in trimmed.runes) {
    final char = String.fromCharCode(codePoint);
    buffer.write(char);
    runLength += 1;
    if (_isUpdateValueBreakPoint(char) || runLength >= 16) {
      buffer.write('\u{200B}');
      runLength = 0;
    }
  }
  return buffer.toString();
}

bool _isUpdateValueBreakPoint(String char) {
  return switch (char) {
    '-' || '_' || '.' || '/' || '+' => true,
    _ => false,
  };
}
