/// 视觉三件套：EmptyState / LoadingState / ErrorState（Task 20 / Req 10.2）。
///
/// - [EmptyState] 沿用 `lib/widgets/empty_state.dart` 中的既有实现，这里
///   重导出，便于调用方统一从 `result_states.dart` 导入。
/// - [LoadingState] 基于纯 Flutter `AnimationController` 实现 shimmer 条带，
///   不引入 `shimmer` 包，保持依赖表干净。
/// - [ErrorState] 接收 `Object error, VoidCallback? onRetry`，统一错误展示。
library;

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
export 'empty_state.dart' show EmptyState;

/// 加载中占位：带 shimmer 扫光的骨架条。
class LoadingState extends StatefulWidget {
  /// 可选的加载文案。
  final String? message;

  /// 占位条的数量。
  final int lines;

  const LoadingState({super.key, this.message, this.lines = 3});

  @override
  State<LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<LoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceXxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < widget.lines; i++) ...[
              _ShimmerBar(
                controller: _controller,
                width: i == 0 ? 220 : 180 - (i * 20).toDouble(),
              ),
              const SizedBox(height: DesignTokens.spaceSm),
            ],
            if (widget.message != null) ...[
              const SizedBox(height: DesignTokens.spaceLg),
              Text(
                widget.message!,
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeSm,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShimmerBar extends StatelessWidget {
  final AnimationController controller;
  final double width;

  const _ShimmerBar({required this.controller, required this.width});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return ClipRRect(
          borderRadius: DesignTokens.borderRadiusSm,
          child: SizedBox(
            width: width,
            height: 12,
            child: ShaderMask(
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment(-1.0 + 2.0 * t, 0),
                  end: Alignment(0.0 + 2.0 * t, 0),
                  colors: const [
                    DesignTokens.resultLoadingShimmerBase,
                    DesignTokens.resultLoadingShimmerHighlight,
                    DesignTokens.resultLoadingShimmerBase,
                  ],
                ).createShader(rect);
              },
              child: Container(color: DesignTokens.resultLoadingShimmerBase),
            ),
          ),
        );
      },
    );
  }
}

/// 错误态占位：带重试按钮的错误展示。
class ErrorState extends StatelessWidget {
  /// 具体错误对象；调用 `toString()` 展示。
  final Object error;

  /// 可选重试回调。为 null 时按钮隐藏。
  final VoidCallback? onRetry;

  /// 可选的标题文案，默认 "出错了"。
  final String title;

  const ErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.title = '出错了',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.space3xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 56,
              color: DesignTokens.resultError,
            ),
            const SizedBox(height: DesignTokens.spaceMd),
            Text(
              title,
              style: const TextStyle(
                fontSize: DesignTokens.fontSizeMd,
                fontWeight: DesignTokens.fontWeightSemiBold,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceXs),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeSm,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: DesignTokens.spaceLg),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
