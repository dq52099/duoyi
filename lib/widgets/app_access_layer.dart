import 'package:flutter/material.dart';

import '../services/account_local_data_cleaner.dart';
import '../services/app_access_route_gate.dart';

/// Covers the complete Navigator without replacing its routes or form state.
class AppAccessLayer extends StatefulWidget {
  const AppAccessLayer({
    super.key,
    required this.child,
    required this.locked,
    required this.mustUpdate,
    required this.routes,
    required this.lockOverlay,
    required this.updateOverlay,
  });

  final Widget child;
  final bool locked;
  final bool mustUpdate;
  final AppAccessRouteGate routes;
  final Widget lockOverlay;
  final Widget updateOverlay;

  @override
  State<AppAccessLayer> createState() => _AppAccessLayerState();
}

class _AppAccessLayerState extends State<AppAccessLayer> {
  FocusNode? _previousFocus;
  Route<dynamic>? _previousRoute;
  int? _previousAccount;
  int _focusGeneration = 0;
  final _updateFocus = FocusScopeNode();

  bool get _blocked => widget.locked || widget.mustUpdate;

  @override
  void didUpdateWidget(covariant AppAccessLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mustUpdate && !oldWidget.mustUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.mustUpdate) _updateFocus.requestFocus();
      });
    }
    final wasBlocked = oldWidget.locked || oldWidget.mustUpdate;
    if (_blocked == wasBlocked) return;
    final generation = ++_focusGeneration;
    if (_blocked) {
      _previousFocus = FocusManager.instance.primaryFocus;
      _previousRoute = widget.routes.currentRoute;
      _previousAccount = AccountLocalDataCleaner.accountDataGeneration;
      _previousFocus?.unfocus();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final focus = _previousFocus;
        if (!mounted ||
            generation != _focusGeneration ||
            _blocked ||
            focus?.context == null ||
            !focus!.canRequestFocus ||
            widget.routes.currentRoute != _previousRoute ||
            _previousAccount != AccountLocalDataCleaner.accountDataGeneration) {
          return;
        }
        focus.requestFocus();
        _previousFocus = null;
      });
    }
  }

  @override
  void dispose() {
    _focusGeneration++;
    _updateFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(
          absorbing: _blocked,
          child: ExcludeFocus(
            excluding: _blocked,
            child: ExcludeSemantics(excluding: _blocked, child: widget.child),
          ),
        ),
        if (widget.locked && !widget.mustUpdate)
          Positioned.fill(
            child: FocusScope(
              autofocus: true,
              child: Overlay.wrap(child: Material(child: widget.lockOverlay)),
            ),
          ),
        Positioned.fill(
          child: Offstage(
            offstage: !widget.mustUpdate,
            child: FocusScope(
              node: _updateFocus,
              autofocus: widget.mustUpdate,
              canRequestFocus: widget.mustUpdate,
              child: Overlay.wrap(
                child: Stack(children: [widget.updateOverlay]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
