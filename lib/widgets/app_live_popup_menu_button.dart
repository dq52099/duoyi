import 'package:flutter/material.dart';

/// A [PopupMenuButton] whose retained menu route inherits live ancestor themes
/// above the [Navigator] rather than freezing local [Theme] wrappers via
/// [InheritedTheme.capture].
class AppLivePopupMenuButton<T> extends PopupMenuButton<T> {
  const AppLivePopupMenuButton({
    super.key,
    required super.itemBuilder,
    super.initialValue,
    super.onOpened,
    super.onSelected,
    super.onCanceled,
    super.tooltip,
    super.elevation,
    super.shadowColor,
    super.surfaceTintColor,
    super.padding,
    super.menuPadding,
    super.child,
    super.borderRadius,
    super.splashRadius,
    super.icon,
    super.iconSize,
    super.offset,
    super.enabled,
    super.shape,
    super.color,
    super.iconColor,
    super.enableFeedback,
    super.constraints,
    super.position,
    super.clipBehavior,
    super.useRootNavigator,
    super.popUpAnimationStyle,
    super.routeSettings,
    super.style,
    super.requestFocus,
  });

  @override
  PopupMenuButtonState<T> createState() => _AppLivePopupMenuButtonState<T>();
}

class _AppLivePopupMenuButtonState<T> extends PopupMenuButtonState<T> {
  bool _isLiveMenuExpanded = false;
  RelativeRect? _lastPosition;
  late PopupMenuThemeData _popupMenuTheme;
  RenderBox? _cachedButtonRenderBox;
  RenderBox? _cachedOverlayRenderBox;

  bool get _canRequestFocus {
    final NavigationMode mode =
        MediaQuery.maybeNavigationModeOf(context) ?? NavigationMode.traditional;
    return switch (mode) {
      NavigationMode.traditional => widget.enabled,
      NavigationMode.directional => true,
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateLiveCachedObjects();
  }

  void _updateLiveCachedObjects() {
    if (!mounted) {
      return;
    }
    _popupMenuTheme = PopupMenuTheme.of(context);
    final RenderObject? buttonRenderObject = context.findRenderObject();
    if (buttonRenderObject is RenderBox) {
      _cachedButtonRenderBox = buttonRenderObject;
    }
    try {
      final NavigatorState navigator = Navigator.of(
        context,
        rootNavigator: widget.useRootNavigator,
      );
      final RenderObject? overlayRenderObject = navigator.overlay?.context
          .findRenderObject();
      if (overlayRenderObject is RenderBox) {
        _cachedOverlayRenderBox = overlayRenderObject;
      }
    } catch (_) {
      _cachedButtonRenderBox = null;
      _cachedOverlayRenderBox = null;
    }
  }

  RelativeRect _getDefaultPosition(BoxConstraints constraints) {
    return _lastPosition ??
        RelativeRect.fromSize(Rect.zero, constraints.biggest);
  }

  RelativeRect _positionBuilder(BuildContext _, BoxConstraints constraints) {
    if (!mounted) {
      return _getDefaultPosition(constraints);
    }
    final RenderBox? button = _cachedButtonRenderBox;
    final RenderBox? overlay = _cachedOverlayRenderBox;
    if (button == null ||
        overlay == null ||
        !button.attached ||
        !overlay.attached) {
      return _getDefaultPosition(constraints);
    }
    final PopupMenuPosition popupMenuPosition =
        widget.position ?? _popupMenuTheme.position ?? PopupMenuPosition.over;
    late Offset offset;
    switch (popupMenuPosition) {
      case PopupMenuPosition.over:
        offset = widget.offset;
      case PopupMenuPosition.under:
        offset = Offset(0.0, button.size.height) + widget.offset;
        if (widget.child == null) {
          offset -= Offset(0.0, widget.padding.vertical / 2);
        }
    }
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(offset, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero) + offset,
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    return _lastPosition = position;
  }

  @override
  void showButtonMenu() {
    _updateLiveCachedObjects();
    final List<PopupMenuEntry<T>> items = widget.itemBuilder(context);
    if (items.isEmpty) {
      return;
    }
    widget.onOpened?.call();
    setState(() {
      _isLiveMenuExpanded = true;
    });
    final NavigatorState navigator = Navigator.of(
      context,
      rootNavigator: widget.useRootNavigator,
    );
    // Open from the Navigator's overlay context so showMenu does not freeze
    // local route/control ThemeData wrappers in CapturedThemes.
    final BuildContext menuContext = navigator.overlay?.context ?? context;
    showMenu<T?>(
      context: menuContext,
      elevation: widget.elevation,
      shadowColor: widget.shadowColor,
      surfaceTintColor: widget.surfaceTintColor,
      items: items,
      initialValue: widget.initialValue,
      positionBuilder: _positionBuilder,
      shape: widget.shape,
      menuPadding: widget.menuPadding,
      color: widget.color,
      constraints: widget.constraints,
      clipBehavior: widget.clipBehavior,
      useRootNavigator: widget.useRootNavigator,
      popUpAnimationStyle: widget.popUpAnimationStyle,
      routeSettings: widget.routeSettings,
      requestFocus: widget.requestFocus,
    ).then<void>((T? newValue) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _isLiveMenuExpanded = false;
      });
      if (newValue == null) {
        widget.onCanceled?.call();
        return null;
      }
      widget.onSelected?.call(newValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    final IconThemeData iconTheme = IconTheme.of(context);
    final PopupMenuThemeData popupMenuTheme = PopupMenuTheme.of(context);
    final bool enableFeedback =
        widget.enableFeedback ?? popupMenuTheme.enableFeedback ?? true;

    assert(debugCheckHasMaterialLocalizations(context));

    if (widget.child != null) {
      final Widget child = Tooltip(
        message:
            widget.tooltip ?? MaterialLocalizations.of(context).showMenuTooltip,
        child: InkWell(
          borderRadius: widget.borderRadius,
          onTap: widget.enabled ? showButtonMenu : null,
          canRequestFocus: _canRequestFocus,
          radius: widget.splashRadius,
          enableFeedback: enableFeedback,
          child: widget.child,
        ),
      );
      final MaterialTapTargetSize tapTargetSize =
          widget.style?.tapTargetSize ?? MaterialTapTargetSize.shrinkWrap;
      if (tapTargetSize == MaterialTapTargetSize.padded) {
        return Semantics(
          expanded: _isLiveMenuExpanded,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: kMinInteractiveDimension,
              minHeight: kMinInteractiveDimension,
            ),
            child: child,
          ),
        );
      }
      return Semantics(expanded: _isLiveMenuExpanded, child: child);
    }

    return Semantics(
      child: IconButton(
        key: StandardComponentType.moreButton.key,
        icon: Semantics(
          expanded: _isLiveMenuExpanded,
          child: widget.icon ?? Icon(Icons.adaptive.more),
        ),
        padding: widget.padding,
        splashRadius: widget.splashRadius,
        iconSize: widget.iconSize ?? popupMenuTheme.iconSize ?? iconTheme.size,
        color: widget.iconColor ?? popupMenuTheme.iconColor ?? iconTheme.color,
        tooltip:
            widget.tooltip ?? MaterialLocalizations.of(context).showMenuTooltip,
        onPressed: widget.enabled ? showButtonMenu : null,
        enableFeedback: enableFeedback,
        style: widget.style,
      ),
    );
  }
}
