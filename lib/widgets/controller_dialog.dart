import 'dart:async';

import 'package:flutter/material.dart';

/// Keeps text controllers alive until the dialog's exit animation unmounts
/// its inputs. Callers capture submitted text before awaiting further work.
Future<T?> showControllerDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required List<TextEditingController> controllers,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
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
