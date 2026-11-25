import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/preferences_provider.dart';

enum AppHaptic { lightImpact, mediumImpact, heavyImpact, selectionClick }

/// Read the live preference immediately before sending feedback to the device.
Future<void> performAppHaptic(
  BuildContext context,
  AppHaptic kind, {
  bool Function()? isCurrent,
}) async {
  if (!context.mounted || isCurrent?.call() == false) return;
  if (!(context.read<PreferencesProvider?>()?.haptic ?? true)) return;

  try {
    switch (kind) {
      case AppHaptic.lightImpact:
        await HapticFeedback.lightImpact();
      case AppHaptic.mediumImpact:
        await HapticFeedback.mediumImpact();
      case AppHaptic.heavyImpact:
        await HapticFeedback.heavyImpact();
      case AppHaptic.selectionClick:
        await HapticFeedback.selectionClick();
    }
  } catch (_) {
    // Feedback availability does not change the result of a committed action.
  }
}
