import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_brand.dart';
import '../core/i18n.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/brand_background.dart';
import 'desktop_command_palette.dart';
import 'desktop_sidebar.dart';
import 'desktop_topbar.dart';
import 'desktop_web_nav.dart';
import 'desktop_web_tokens.dart';
import 'views/desktop_almanac_view.dart';
import 'views/desktop_calendar_view.dart';
import 'views/desktop_embedded_page.dart';
import 'views/desktop_focus_view.dart';
import 'views/desktop_habit_view.dart';
import 'views/desktop_today_view.dart';
import 'views/desktop_todo_view.dart';

/// Top-level Desktop Web productivity workspace shell hosting the persistent
/// 248px sidebar, unified 56px topbar, Ctrl/Cmd+K command palette, and
/// multi-pane desktop views inside a nested Navigator.
class DesktopWebWorkspace extends StatefulWidget {
  final DesktopWebDestination initialDestination;
  final DesktopWebNavController? controller;

  const DesktopWebWorkspace({
    super.key,
    this.initialDestination = DesktopWebDestination.today,
    this.controller,
  });

  @override
  State<DesktopWebWorkspace> createState() => _DesktopWebWorkspaceState();
}

class _DesktopWebWorkspaceState extends State<DesktopWebWorkspace> {
  DesktopWebNavController? _ownedController;
  late DesktopWebNavController _controller;
  final GlobalKey<NavigatorState> _contentNavigatorKey =
      GlobalKey<NavigatorState>();
  final Set<DesktopWebDestination> _builtPrimaryViews =
      <DesktopWebDestination>{};
  bool _paletteOpen = false;
  bool _quickCreateOpen = false;

  static const List<DesktopWebDestination> _primaryOrder =
      <DesktopWebDestination>[
        DesktopWebDestination.today,
        DesktopWebDestination.todo,
        DesktopWebDestination.habit,
        DesktopWebDestination.calendar,
        DesktopWebDestination.focus,
        DesktopWebDestination.almanac,
      ];

  static bool _isNativeView(DesktopWebDestination dest) =>
      dest.isPrimaryView || dest == DesktopWebDestination.almanac;

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  @override
  void didUpdateWidget(DesktopWebWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detachController(oldWidget.controller);
      _attachController();
    } else if (widget.controller == null &&
        oldWidget.initialDestination != widget.initialDestination) {
      _controller.navigateTo(widget.initialDestination);
    }
  }

  void _attachController() {
    if (widget.controller != null) {
      _ownedController?.dispose();
      _ownedController = null;
      _controller = widget.controller!;
    } else {
      _ownedController ??= DesktopWebNavController(
        initialDestination: widget.initialDestination,
      );
      _controller = _ownedController!;
    }
    if (_isNativeView(_controller.destination)) {
      _builtPrimaryViews.add(_controller.destination);
    } else {
      _builtPrimaryViews.add(DesktopWebDestination.today);
    }
    _controller.onOpenCommandPalette = _handleOpenCommandPalette;
    _controller.onQuickCreate = _handleQuickCreate;
    _controller.onResetNestedRoutes = _resetNestedRoutes;
  }

  void _detachController(DesktopWebNavController? previous) {
    if (previous != null) {
      if (identical(previous.onOpenCommandPalette, _handleOpenCommandPalette)) {
        previous.onOpenCommandPalette = null;
      }
      if (identical(previous.onQuickCreate, _handleQuickCreate)) {
        previous.onQuickCreate = null;
      }
      if (identical(previous.onResetNestedRoutes, _resetNestedRoutes)) {
        previous.onResetNestedRoutes = null;
      }
    }
  }

  @override
  void dispose() {
    _detachController(widget.controller);
    _ownedController?.dispose();
    super.dispose();
  }

  void _resetNestedRoutes() {
    final nav = _contentNavigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
  }

  Future<void> _handleOpenCommandPalette({
    DesktopCommandMode initialMode = DesktopCommandMode.search,
    String? initialQuery,
  }) async {
    if (!mounted || _paletteOpen) return;
    _paletteOpen = true;
    try {
      await showDesktopCommandPalette(
        context,
        controller: _controller,
        initialMode: initialMode,
        initialQuery: initialQuery,
      );
    } finally {
      _paletteOpen = false;
    }
  }

  Future<void> _handleQuickCreate(DesktopQuickCreateKind kind) async {
    if (!mounted || _quickCreateOpen) return;
    _quickCreateOpen = true;
    try {
      await showDesktopQuickCreateDialog(
        context,
        navController: _controller,
        kind: kind,
      );
    } finally {
      _quickCreateOpen = false;
    }
  }

  void _startFocus({String? taskTitle}) {
    final pomodoro = context.read<PomodoroProvider?>();
    if (pomodoro != null) {
      if (taskTitle != null && taskTitle.trim().isNotEmpty) {
        pomodoro.setTaskName(taskTitle.trim());
      }
      pomodoro.startIfIdle();
    }
    _controller.navigateTo(DesktopWebDestination.focus);
  }

  @override
  Widget build(BuildContext context) {
    AppBrand activeBrand;
    try {
      activeBrand = context.select<ThemeProvider?, AppBrand>(
        (tp) => tp?.brand ?? AppBrands.defaultBrand,
      );
    } catch (_) {
      activeBrand = AppBrands.defaultBrand;
    }

    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final workspaceTheme = DesktopWebTokens.buildWorkspaceTheme(
            brand: activeBrand,
            darkOverride: _controller.darkModeOverride,
            frostedOverride: _controller.frostedOverride,
          );
          if (_isNativeView(_controller.destination)) {
            _builtPrimaryViews.add(_controller.destination);
          }

          return Theme(
            data: workspaceTheme,
            child: DesktopWebScope(
              controller: _controller,
              child: Builder(
                builder: (themedContext) {
                  final tokens = DesktopWebTokens.of(themedContext);
                  return CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.keyK,
                        meta: true,
                      ): () => _handleOpenCommandPalette(),
                      const SingleActivator(
                        LogicalKeyboardKey.keyK,
                        control: true,
                      ): () => _handleOpenCommandPalette(),
                    },
                    child: Focus(
                      autofocus: true,
                      child: Scaffold(
                        backgroundColor: tokens.canvasBackground,
                        body: Stack(
                          fit: StackFit.expand,
                          children: [
                            _WorkspaceCanvasBackdrop(
                              brand: activeBrand,
                              tokens: tokens,
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DesktopSidebar(controller: _controller),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      DesktopTopBar(controller: _controller),
                                      Expanded(
                                        child: HeroControllerScope.none(
                                          child: Navigator(
                                            key: _contentNavigatorKey,
                                            onGenerateRoute: (_) =>
                                                PageRouteBuilder<void>(
                                                  transitionDuration:
                                                      Duration.zero,
                                                  reverseTransitionDuration:
                                                      Duration.zero,
                                                  pageBuilder: (_, _, _) =>
                                                      _WorkspaceContentStage(
                                                        controller: _controller,
                                                        builtPrimaryViews:
                                                            _builtPrimaryViews,
                                                        primaryOrder:
                                                            _primaryOrder,
                                                        onStartFocus:
                                                            _startFocus,
                                                      ),
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WorkspaceContentStage extends StatelessWidget {
  final DesktopWebNavController controller;
  final Set<DesktopWebDestination> builtPrimaryViews;
  final List<DesktopWebDestination> primaryOrder;
  final void Function({String? taskTitle}) onStartFocus;

  const _WorkspaceContentStage({
    required this.controller,
    required this.builtPrimaryViews,
    required this.primaryOrder,
    required this.onStartFocus,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final dest = controller.destination;
        final isNative =
            dest.isPrimaryView || dest == DesktopWebDestination.almanac;
        if (isNative) {
          builtPrimaryViews.add(dest);
        }
        final primaryIndex = primaryOrder.indexOf(
          isNative ? dest : DesktopWebDestination.today,
        );

        final primaryStack = IndexedStack(
          index: primaryIndex < 0 ? 0 : primaryIndex,
          children: primaryOrder
              .map(
                (viewDest) => builtPrimaryViews.contains(viewDest)
                    ? TickerMode(
                        enabled: isNative && viewDest == dest,
                        child: _buildPrimaryView(viewDest),
                      )
                    : SizedBox.shrink(
                        key: ValueKey('desktop_lazy_${viewDest.name}'),
                      ),
              )
              .toList(growable: false),
        );

        final Widget activeCanvas = Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: !isNative,
              child: TickerMode(
                enabled: isNative,
                child: primaryStack,
              ),
            ),
            if (!isNative)
              DesktopEmbeddedPage(
                key: ValueKey('desktop_embedded_${dest.name}'),
                destination: dest,
                controller: controller,
                onNavigate: (target) => controller.navigateTo(target),
              ),
          ],
        );

        return _WorkspaceStageTransition(
          destination: dest,
          child: activeCanvas,
        );
      },
    );
  }

  Widget _buildPrimaryView(DesktopWebDestination dest) {
    return switch (dest) {
      DesktopWebDestination.today => DesktopTodayView(
        controller: controller,
        onNavigate: (target) => controller.navigateTo(target),
        onOpenTodo: (todoId) => controller.navigateTo(
          DesktopWebDestination.todo,
          selectedTodoId: todoId,
        ),
        onStartFocus: onStartFocus,
      ),
      DesktopWebDestination.todo => DesktopTodoView(
        controller: controller,
        initialSelectedTodoId: controller.selectedTodoId,
        onStartFocus: onStartFocus,
      ),
      DesktopWebDestination.habit => DesktopHabitView(
        controller: controller,
        onNavigate: (target) => controller.navigateTo(target),
      ),
      DesktopWebDestination.calendar => DesktopCalendarView(
        controller: controller,
        initialDate: controller.focusedCalendarDate,
        onNavigate: (target) => controller.navigateTo(target),
        onOpenTodo: (todoId) => controller.navigateTo(
          DesktopWebDestination.todo,
          selectedTodoId: todoId,
        ),
      ),
      DesktopWebDestination.focus => DesktopFocusView(
        controller: controller,
        onNavigate: (target) => controller.navigateTo(target),
      ),
      DesktopWebDestination.almanac => DesktopAlmanacView(
        controller: controller,
        initialDate: controller.focusedCalendarDate,
        initialTab: controller.almanacTabIndex,
        onNavigate: (target) => controller.navigateTo(target),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _WorkspaceStageTransition extends StatefulWidget {
  final DesktopWebDestination destination;
  final Widget child;

  const _WorkspaceStageTransition({
    required this.destination,
    required this.child,
  });

  @override
  State<_WorkspaceStageTransition> createState() =>
      _WorkspaceStageTransitionState();
}

class _WorkspaceStageTransitionState extends State<_WorkspaceStageTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      value: 1.0,
    );
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _opacity = Tween<double>(begin: 0.72, end: 1.0).animate(curved);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.005),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void didUpdateWidget(covariant _WorkspaceStageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination != widget.destination) {
      final disableAnimations =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnimations) {
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }
}

class _WorkspaceCanvasBackdrop extends StatelessWidget {
  final AppBrand brand;
  final DesktopWebTokens tokens;

  const _WorkspaceCanvasBackdrop({
    required this.brand,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    if (tokens.isLiquidGlass) {
      return IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _DesktopGlassAmbientPainter(isDark: tokens.isDark),
          ),
        ),
      );
    }
    if (brand.backgroundAsset != null) {
      return IgnorePointer(
        child: BrandBackground(
          overlayOpacity: tokens.isDark ? 0.86 : 0.84,
          child: const SizedBox.expand(),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _DesktopGlassAmbientPainter extends CustomPainter {
  final bool isDark;

  const _DesktopGlassAmbientPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [
                Color(0xFF0C1220),
                Color(0xFF10192D),
                Color(0xFF0E1728),
              ]
            : const [
                Color(0xFFE3EDF9),
                Color(0xFFEBF0F8),
                Color(0xFFE1ECF8),
              ],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    final glow1Center = Offset(size.width * 0.84, size.height * 0.14);
    final glow1Radius = size.shortestSide * 0.65;
    final glow1Paint = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? const [Color(0x40214B8C), Color(0x000D1320)]
            : const [Color(0x88CFE2FA), Color(0x00EBF0F8)],
      ).createShader(
        Rect.fromCircle(center: glow1Center, radius: glow1Radius),
      );
    canvas.drawCircle(glow1Center, glow1Radius, glow1Paint);

    final glow2Center = Offset(size.width * 0.18, size.height * 0.78);
    final glow2Radius = size.shortestSide * 0.58;
    final glow2Paint = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? const [Color(0x331B5B78), Color(0x000D1320)]
            : const [Color(0x72D1EEF8), Color(0x00EBF0F8)],
      ).createShader(
        Rect.fromCircle(center: glow2Center, radius: glow2Radius),
      );
    canvas.drawCircle(glow2Center, glow2Radius, glow2Paint);

    final glow3Center = Offset(size.width * 0.10, size.height * 0.34);
    final glow3Radius = size.shortestSide * 0.52;
    final glow3Paint = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? [
                const Color(0xFF4F63D6).withValues(alpha: 0.22),
                const Color(0x000D1320),
              ]
            : [
                const Color(0xFF7B93F5).withValues(alpha: 0.22),
                const Color(0x00EBF0F8),
              ],
      ).createShader(
        Rect.fromCircle(center: glow3Center, radius: glow3Radius),
      );
    canvas.drawCircle(glow3Center, glow3Radius, glow3Paint);
  }

  @override
  bool shouldRepaint(covariant _DesktopGlassAmbientPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
