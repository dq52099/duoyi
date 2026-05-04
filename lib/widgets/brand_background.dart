import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

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
        if (brand.backgroundAsset != null)
          Image.asset(
            brand.backgroundAsset!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(color: brand.backgroundOverlay),
          )
        else
          Container(color: brand.backgroundOverlay),
        Container(
          color: brand.backgroundOverlay.withValues(alpha: brand.backgroundOverlayOpacity),
        ),
        child,
      ],
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
