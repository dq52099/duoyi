import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import 'surface_components.dart';

/// 关键本地数据加载门禁界面。
///
/// 当应用启动检测到关键本地存储尚未就绪时显示此全屏占位：
/// - 加载中状态显示静默等待文案，支持 Reduced Motion 静态指示器；
/// - 失败状态显示本地化提示文案及重试按钮；
/// - 监听 [I18n.localeListenable]，语言切换时即时响应；
/// - 适配默认 iOS 与液态玻璃（liquidGlass）主题观感。
class CriticalStorageGate extends StatelessWidget {
  final bool busy;
  final bool failed;
  final VoidCallback onRetry;

  const CriticalStorageGate({
    super.key,
    required this.busy,
    required this.failed,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isEnglish = locale == AppLocale.en;
        final showError = failed && !busy;

        final media = MediaQuery.maybeOf(context);
        final reduceMotion =
            media?.disableAnimations == true ||
            media?.accessibleNavigation == true;

        final titleStyle = TextStyle(
          fontSize: theme.textTheme.titleLarge?.fontSize ?? 18.0,
          fontWeight: FontWeight.normal,
          color: cs.onSurface,
          height: 1.3,
        );

        final descriptionStyle = TextStyle(
          fontSize: theme.textTheme.bodyMedium?.fontSize ?? 14.0,
          fontWeight: FontWeight.normal,
          color: cs.onSurface,
          height: 1.45,
        );

        final busyTextStyle = TextStyle(
          fontSize: theme.textTheme.bodyMedium?.fontSize ?? 14.0,
          fontWeight: FontWeight.normal,
          color: cs.onSurface,
          height: 1.45,
        );

        final buttonTextStyle = TextStyle(
          fontSize: theme.textTheme.labelLarge?.fontSize ?? 14.0,
          fontWeight: FontWeight.normal,
        );

        return Scaffold(
          key: const ValueKey('critical_storage_gate'),
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const verticalPadding = 24.0;
                final availableHeight = constraints.hasBoundedHeight
                    ? math.max(
                        0.0,
                        constraints.maxHeight - (verticalPadding * 2),
                      )
                    : 0.0;

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: verticalPadding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: availableHeight),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: AppSurfaceCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 32,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showError) ...[
                                Center(
                                  child: Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: cs.error.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      Icons.error_outline_rounded,
                                      size: 30,
                                      color: cs.error,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  isEnglish
                                      ? 'Unable to load local data'
                                      : '无法加载本地数据',
                                  textAlign: TextAlign.center,
                                  style: titleStyle,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isEnglish
                                      ? 'Please retry to continue.'
                                      : '请重试以继续。',
                                  textAlign: TextAlign.center,
                                  style: descriptionStyle,
                                ),
                                const SizedBox(height: 24),
                                FilledButton(
                                  key: const ValueKey('critical_storage_retry'),
                                  onPressed: onRetry,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(88, 48),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: Text(
                                    I18n.tr('action.retry'),
                                    style: buttonTextStyle,
                                  ),
                                ),
                              ] else ...[
                                Center(
                                  child: reduceMotion
                                      ? Semantics(
                                          label: isEnglish
                                              ? 'Loading local data'
                                              : '正在加载本地数据',
                                          child: Container(
                                            width: 56,
                                            height: 56,
                                            decoration: BoxDecoration(
                                              color: cs.primary.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Icon(
                                              Icons.hourglass_empty_rounded,
                                              size: 28,
                                              color: cs.primary,
                                            ),
                                          ),
                                        )
                                      : SizedBox(
                                          width: 36,
                                          height: 36,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  cs.primary,
                                                ),
                                            semanticsLabel: isEnglish
                                                ? 'Loading local data'
                                                : '正在加载本地数据',
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  isEnglish
                                      ? 'Loading local data'
                                      : '正在加载本地数据',
                                  textAlign: TextAlign.center,
                                  style: busyTextStyle,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
