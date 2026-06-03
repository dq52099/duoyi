import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'surface_components.dart';

/// Wraps any child with the active theme's background image and overlay.
/// Default brand has no asset, so we just render the child on top of the
/// scaffold's normal background.
class BrandBackground extends StatelessWidget {
  final Widget child;
  const BrandBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final brand = context.watch<ThemeProvider>().brand;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: brand.backgroundAsset != null
              ? Image.asset(
                  brand.backgroundAsset!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stack) =>
                      Container(color: brand.backgroundOverlay),
                )
              : Container(color: brand.backgroundOverlay),
        ),
        RepaintBoundary(
          child: Container(
            color: brand.backgroundOverlay.withValues(
              alpha: brand.backgroundOverlayOpacity,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Keeps route-pushed transparent pages from falling through to the Navigator's
/// black backing surface.
class BrandRouteSurface extends StatelessWidget {
  final Widget child;
  const BrandRouteSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Material(
      color: routeBackground,
      child: BrandBackground(child: AppSecondaryControlTheme(child: child)),
    );
  }
}

/// A scaffold that shows transparent surfaces on top of the brand background.
/// Use this in screens so they don't paint a solid scaffold color over the
/// brand image.
class BrandScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool extendBodyBehindAppBar;

  const BrandScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.extendBodyBehindAppBar = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return ColoredBox(
      color: routeBackground,
      child: BrandBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: extendBodyBehindAppBar,
          appBar: appBar,
          body: body,
          floatingActionButton: floatingActionButton,
          bottomNavigationBar: bottomNavigationBar,
        ),
      ),
    );
  }
}
