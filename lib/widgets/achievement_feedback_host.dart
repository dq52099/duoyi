import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/achievement_ui_copy.dart';
import '../core/achievements.dart';
import '../core/i18n.dart';
import '../providers/achievement_provider.dart';
import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/app_update_service.dart';
import '../services/settings_action_origin.dart';

/// Owns transient achievement feedback without adding to other pages' snackbars.
class AchievementFeedbackHost extends StatefulWidget {
  final Widget child;
  const AchievementFeedbackHost({super.key, required this.child});
  @override
  State<AchievementFeedbackHost> createState() =>
      _AchievementFeedbackHostState();
}

class _AchievementFeedbackHostState extends State<AchievementFeedbackHost> {
  AchievementProvider? _provider;
  Listenable? _ownerChanges;
  final _pending = Queue<Achievement>();
  Achievement? _visible;
  SettingsActionOrigin? _origin;
  int? _generation;
  Timer? _timer;
  bool _scheduled = false;

  bool get _valid =>
      mounted &&
      _origin?.isCurrent(checkRoute: false) == true &&
      identical(context.read<AchievementProvider?>(), _provider) &&
      _provider?.storageGeneration == _generation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.watch<AchievementProvider>();
    final auth = context.watch<AuthProvider?>();
    final lock = context.watch<AppLockProvider?>();
    final update = context.watch<AppUpdateService?>();
    final preferences = context.watch<PreferencesProvider?>();
    if (!identical(_provider, provider)) {
      _provider?.removeListener(_receive);
      _clear();
      _provider = provider;
      provider.addListener(_receive);
    }
    _ownerChanges?.removeListener(_checkOwner);
    _ownerChanges = Listenable.merge([
      auth,
      lock,
      update,
      preferences,
      AccountLocalDataCleaner.accountDataGenerationListenable,
    ])..addListener(_checkOwner);
    _receive();
  }

  void _clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _visible = null;
    _origin = null;
    _generation = null;
  }

  void _checkOwner() {
    if (_origin != null && !_valid) {
      // Clear synchronously; rebuild at a safe frame boundary.
      _clear();
      _schedule();
    }
  }

  void _receive() {
    _checkOwner();
    final incoming = _provider!.takeUnlockedFeedback();
    if (incoming.isEmpty) return;
    final origin = SettingsActionOrigin(context);
    if (!origin.isCurrent(checkRoute: false)) return;
    _origin ??= origin;
    _generation ??= _provider!.storageGeneration;
    _pending.addAll(incoming);
    _schedule();
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (_origin != null && !_valid) _clear();
      if (_visible == null && _pending.isNotEmpty) {
        _visible = _pending.removeFirst();
        if (!MediaQuery.accessibleNavigationOf(context)) {
          _timer = Timer(const Duration(seconds: 4), () {
            if (mounted && !MediaQuery.accessibleNavigationOf(context)) {
              _advance();
            }
          });
        }
      }
      setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _advance() {
    if (!mounted) return;
    _timer?.cancel();
    _visible = null;
    if (!_valid || _pending.isEmpty) _clear();
    setState(() {});
    _schedule();
  }

  @override
  void dispose() {
    _provider?.removeListener(_receive);
    _ownerChanges?.removeListener(_checkOwner);
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = _visible;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (badge != null && _valid)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Material(
                    key: const ValueKey('achievement-feedback'),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.22),
                        width: 0.6,
                      ),
                    ),
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                      child: Row(
                        children: [
                          Icon(badge.icon, color: badge.color, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Semantics(
                              liveRegion: true,
                              child: ValueListenableBuilder<AppLocale>(
                                valueListenable: I18n.localeListenable,
                                builder: (context, _, _) => Text(
                                  AchievementUiCopy.unlockMessage(badge),
                                ),
                              ),
                            ),
                          ),
                          ValueListenableBuilder<AppLocale>(
                            valueListenable: I18n.localeListenable,
                            // This host sits above Navigator's Overlay. Keep the
                            // accessible label without requiring a tooltip overlay.
                            builder: (context, _, _) => Semantics(
                              label: AchievementUiCopy.text('关闭', 'Close'),
                              button: true,
                              child: IconButton(
                                key: const ValueKey(
                                  'achievement-feedback-close',
                                ),
                                onPressed: () {
                                  if (_valid) _advance();
                                },
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
