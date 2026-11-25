import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_brand.dart';
import '../providers/theme_provider.dart';
import 'surface_components.dart' show AppSecondaryControlTheme;

/// Builds a dialog with a live brand scope while its caller owns the route.
/// Does not dispose controllers; the route's content or caller retains ownership.
DialogRoute<T> createControllerDialogRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = true,
  void Function(Route<dynamic>)? onRouteCreated,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  ThemeProvider? themeProvider;
  try {
    themeProvider = Provider.of<ThemeProvider>(context, listen: false);
  } catch (_) {
    themeProvider = null;
  }
  final openingTheme = Theme.of(context);
  final hasSecondaryControlTheme =
      context.findAncestorWidgetOfExactType<AppSecondaryControlTheme>() !=
          null ||
      (openingTheme.inputDecorationTheme.prefixIconConstraints ==
          const BoxConstraints.tightFor(width: 34, height: 34));
  final initialBrandId = themeProvider?.brand.id;

  final route = DialogRoute<T>(
    context: context,
    builder: (dialogContext) {
      if (themeProvider == null || initialBrandId == null) {
        return builder(dialogContext);
      }
      return _ControlledDialogThemeScope(
        themeProvider: themeProvider,
        initialBrandId: initialBrandId,
        openingTheme: openingTheme,
        hasSecondaryControlTheme: hasSecondaryControlTheme,
        builder: builder,
      );
    },
    barrierColor:
        DialogTheme.of(context).barrierColor ??
        openingTheme.dialogTheme.barrierColor ??
        Colors.black54,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  onRouteCreated?.call(route);
  return route;
}

/// Keeps text controllers alive until the dialog's exit animation unmounts
/// its inputs. Callers capture submitted text before awaiting further work.
Future<T?> showControllerDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required List<TextEditingController> controllers,
  void Function(Route<dynamic>)? onRouteCreated,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = createControllerDialogRoute<T>(
    context: context,
    builder: builder,
    onRouteCreated: onRouteCreated,
  );
  void disposeControllers() {
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  var pushed = false;
  try {
    final result = navigator.push<T>(route);
    pushed = true;
    return await result;
  } finally {
    if (pushed) {
      unawaited(route.completed.then((_) => disposeControllers()));
    } else {
      disposeControllers();
    }
  }
}

class _ControlledDialogThemeScope extends StatefulWidget {
  final ThemeProvider themeProvider;
  final String initialBrandId;
  final ThemeData openingTheme;
  final bool hasSecondaryControlTheme;
  final WidgetBuilder builder;

  const _ControlledDialogThemeScope({
    required this.themeProvider,
    required this.initialBrandId,
    required this.openingTheme,
    required this.hasSecondaryControlTheme,
    required this.builder,
  });

  @override
  State<_ControlledDialogThemeScope> createState() =>
      _ControlledDialogThemeScopeState();
}

class _ControlledDialogThemeScopeState
    extends State<_ControlledDialogThemeScope> {
  late String _lastBrandId;
  late ThemeData _lastTheme;

  @override
  void initState() {
    super.initState();
    _lastBrandId = widget.themeProvider.brand.id;
    _lastTheme = widget.themeProvider.brand.theme;
    widget.themeProvider.addListener(_onThemeChanged);
  }

  @override
  void didUpdateWidget(_ControlledDialogThemeScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeProvider != widget.themeProvider) {
      oldWidget.themeProvider.removeListener(_onThemeChanged);
      widget.themeProvider.addListener(_onThemeChanged);
      _lastBrandId = widget.themeProvider.brand.id;
      _lastTheme = widget.themeProvider.brand.theme;
    }
  }

  @override
  void dispose() {
    widget.themeProvider.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    final currentBrand = widget.themeProvider.brand;
    if (currentBrand.id != _lastBrandId || currentBrand.theme != _lastTheme) {
      _lastBrandId = currentBrand.id;
      _lastTheme = currentBrand.theme;
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppBrand currentBrand = widget.themeProvider.brand;
    final isInitialBrand = currentBrand.id == widget.initialBrandId;
    final effectiveTheme = isInitialBrand
        ? widget.openingTheme
        : currentBrand.theme;

    Widget content = Builder(builder: widget.builder);
    if (widget.hasSecondaryControlTheme) {
      content = AppSecondaryControlTheme(child: content);
    }
    return Theme(data: effectiveTheme, child: content);
  }
}
