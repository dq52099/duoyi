import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/lock_screen_ui_copy.dart';
import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/theme_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/app_haptics.dart';
import '../services/app_update_service.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';

/// PIN 解锁页：作为全屏覆盖层挡在主界面之上。
class LockScreen extends StatefulWidget implements LocaleStatePreservingRoute {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _input = '';
  LockScreenError? _error;
  bool _busy = false;
  final FocusNode _focusNode = FocusNode();

  bool get _canSubmit => !_busy && _input.length >= 4 && _input.length <= 8;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _press(String k) {
    if (_busy) return;
    setState(() {
      _error = null;
      if (k == 'del') {
        if (_input.isNotEmpty) {
          _input = _input.substring(0, _input.length - 1);
        }
      } else if (_input.length < 8) {
        _input += k;
      }
    });
  }

  Future<void> _submit() async {
    if (!mounted || _busy || !_canSubmit) return;
    final lock = context.read<AppLockProvider>();
    final accessGeneration = lock.accessGeneration;
    final preferences = context.read<PreferencesProvider?>();
    final preferenceGeneration = preferences?.storageGeneration;
    final auth = context.read<AuthProvider?>();
    final sessionGeneration = auth?.sessionGeneration;
    final wasLoggedIn = auth?.state.isLoggedIn ?? false;
    var userId = auth?.state.userId?.trim();
    final update = context.read<AppUpdateService?>();
    final route = ModalRoute.of(context);
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    AuthSessionLease? lease;
    if (wasLoggedIn) {
      try {
        lease = auth!.captureSessionLease();
      } catch (_) {
        return;
      }
    }
    bool isCurrent() {
      if (!mounted ||
          lock.accessGeneration != accessGeneration ||
          preferences?.storageGeneration != preferenceGeneration ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          ) ||
          (route != null && (!route.isActive || !route.isCurrent))) {
        return false;
      }
      try {
        if (!identical(context.read<AppLockProvider>(), lock) ||
            !identical(context.read<PreferencesProvider?>(), preferences) ||
            !identical(context.read<AuthProvider?>(), auth) ||
            !identical(context.read<AppUpdateService?>(), update) ||
            update?.mustUpdate == true) {
          return false;
        }
        if (auth != null) {
          final currentUserId = auth.state.userId?.trim();
          if (auth.sessionGeneration != sessionGeneration ||
              auth.state.isLoggedIn != wasLoggedIn ||
              auth.isAccountTransitionInProgress ||
              auth.isLocalAccountDataBlocked ||
              (lease != null && !auth.isSessionLeaseCurrent(lease)) ||
              (userId?.isNotEmpty == true && currentUserId != userId)) {
            return false;
          }
          if (currentUserId?.isNotEmpty == true) userId ??= currentUserId;
        }
        return true;
      } catch (_) {
        return false;
      }
    }

    if (!isCurrent() || !lock.isLocked) return;
    final wasLocked = lock.isLocked;
    final pin = _input;
    setState(() {
      _busy = true;
    });

    try {
      await lock.unlockWith(pin, isCurrent: isCurrent);
      if (!mounted || !isCurrent()) return;

      final actuallyUnlocked = wasLocked && !lock.isLocked;
      bool feedbackCurrent() =>
          isCurrent() && (actuallyUnlocked ? !lock.isLocked : lock.isLocked);
      await performAppHaptic(
        context,
        actuallyUnlocked ? AppHaptic.lightImpact : AppHaptic.heavyImpact,
        isCurrent: feedbackCurrent,
      );
      if (!feedbackCurrent()) return;
      setState(() {
        _error = actuallyUnlocked ? null : LockScreenError.wrongPin;
      });
    } catch (_) {
      bool failureCurrent() => isCurrent() && lock.isLocked;
      if (!mounted || !failureCurrent()) return;
      await performAppHaptic(
        context,
        AppHaptic.heavyImpact,
        isCurrent: failureCurrent,
      );
      if (!failureCurrent()) return;
      setState(() {
        _error = LockScreenError.verificationFailed;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_busy) return KeyEventResult.handled;

    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete) {
      _press('del');
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_canSubmit) {
        _submit();
      }
      return KeyEventResult.handled;
    }

    final char = event.character;
    if (char != null && RegExp(r'^[0-9]$').hasMatch(char)) {
      _press(char);
      return KeyEventResult.handled;
    }

    final digit = _digitFromKey(event.logicalKey);
    if (digit != null) {
      _press(digit);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String? _digitFromKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      return '0';
    }
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      return '1';
    }
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      return '2';
    }
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      return '3';
    }
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      return '4';
    }
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
      return '5';
    }
    if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
      return '6';
    }
    if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
      return '7';
    }
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
      return '8';
    }
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
      return '9';
    }
    return null;
  }

  Color _resolveLockErrorColor(
    BuildContext context, {
    required bool useWideCard,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass =
        !isDark &&
        surfaceStyle != null &&
        (surfaceStyle.cardFillColor?.a ?? 1.0) < 0.8;

    Color worstSurface = cs.surface;
    if (useWideCard) {
      final cardFill = surfaceStyle?.cardFillColor;
      if (cardFill != null) {
        var underCard = cs.surface;
        final shadow = surfaceStyle?.cardShadow;
        if (cardFill.a < 1.0 && shadow != null && shadow.isNotEmpty) {
          for (final entry in shadow) {
            underCard = Color.alphaBlend(entry.color, underCard);
          }
        }
        worstSurface = Color.alphaBlend(cardFill, underCard);
      }
    }

    final preferred = isLiquidGlass ? const Color(0xFFA23535) : cs.error;
    if (appContrastRatio(worstSurface, preferred) >= 4.5) {
      return preferred;
    }
    final target = isDark ? Colors.white : const Color(0xFF111827);
    for (var t = 0.05; t <= 0.60; t += 0.05) {
      final candidate = Color.lerp(preferred, target, t)!;
      if (appContrastRatio(worstSurface, candidate) >= 4.5) {
        return candidate;
      }
    }
    return appReadableForeground(worstSurface, preferred);
  }

  @override
  Widget build(BuildContext context) {
    // LockScreen 以 const 实例挂在 home Stack 中（见 main.dart），语言切换时
    // 父级不会下发新 widget；监听 I18n.localeListenable 让本页在语言热切换时
    // 重建，品牌词条（s.appTitle）与 PIN 文案即时跟随。
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, child) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        String appTitle;
        try {
          appTitle = context.watch<ThemeProvider>().brand.strings.appTitle;
        } catch (_) {
          appTitle = I18n.current == AppLocale.zh ? '多仪' : 'Duoyi';
        }

        final errorText = _error != null
            ? LockScreenUiCopy.errorMessage(_error!)
            : null;

        return Scaffold(
          backgroundColor: cs.surface,
          body: SafeArea(
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: (node, event) => _handleKeyEvent(event),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isLandscape =
                      constraints.maxWidth > constraints.maxHeight &&
                      constraints.maxWidth >= 480;
                  final isShort = constraints.maxHeight < 560;
                  final useWideCard = constraints.maxWidth >= 520 && !isShort;
                  final verticalPadding = isLandscape
                      ? 8.0
                      : (isShort ? 12.0 : 24.0);
                  final horizontalPadding = isLandscape ? 16.0 : 24.0;
                  final availableHeight = constraints.hasBoundedHeight
                      ? (constraints.maxHeight - (verticalPadding * 2)).clamp(
                          0.0,
                          double.infinity,
                        )
                      : 0.0;

                  final headerWidget = Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock,
                        size: isLandscape ? 32 : (isShort ? 36 : 44),
                        color: cs.primary,
                      ),
                      SizedBox(height: isLandscape ? 4 : (isShort ? 6 : 10)),
                      Text(
                        appTitle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: isLandscape ? 3 : (isShort ? 4 : 6)),
                      Text(
                        I18n.tr('app_lock.pin_hint_enter'),
                        style: TextStyle(
                          fontSize: isLandscape ? 13 : 14,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: isLandscape ? 8 : (isShort ? 12 : 20)),
                      Semantics(
                        label: LockScreenUiCopy.enteredDigitsSemantics(
                          _input.length,
                        ),
                        child: SizedBox(
                          height: 16,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _input.length.clamp(0, 8),
                              (i) => Container(
                                key: ValueKey<String>('lock_screen_pin_dot_$i'),
                                width: 12,
                                height: 12,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (errorText != null)
                        Padding(
                          padding: EdgeInsets.only(top: isLandscape ? 6 : 10),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              errorText,
                              style: TextStyle(
                                color: _resolveLockErrorColor(
                                  context,
                                  useWideCard: useWideCard,
                                ),
                                fontSize: isLandscape ? 13 : 14,
                                fontWeight: FontWeight.normal,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );

                  final submitButton = Semantics(
                    button: true,
                    enabled: _canSubmit,
                    label: LockScreenUiCopy.unlock,
                    child: Tooltip(
                      message: _canSubmit ? LockScreenUiCopy.submitTooltip : '',
                      child: FilledButton(
                        key: const ValueKey<String>('lock_screen_submit'),
                        onPressed: _canSubmit ? _submit : null,
                        style: FilledButton.styleFrom(
                          minimumSize: Size(isLandscape ? 180 : 200, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _busy
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        cs.onPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        LockScreenUiCopy.busyMessage,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  LockScreenUiCopy.unlock,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  );

                  final Widget content;
                  if (isLandscape && !useWideCard) {
                    content = Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: headerWidget,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _Keypad(
                                  onTap: _press,
                                  busy: _busy,
                                  compact: true,
                                ),
                                const SizedBox(height: 8),
                                submitButton,
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    final innerColumn = Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        headerWidget,
                        SizedBox(height: isShort ? 12 : 22),
                        _Keypad(onTap: _press, busy: _busy, compact: isShort),
                        SizedBox(height: isShort ? 14 : 22),
                        submitButton,
                      ],
                    );
                    content = useWideCard
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: AppSurfaceCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 24,
                              ),
                              child: innerColumn,
                            ),
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: innerColumn,
                          );
                  }

                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: availableHeight),
                      child: Center(child: content),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Keypad extends StatelessWidget {
  final void Function(String) onTap;
  final bool busy;
  final bool compact;

  const _Keypad({
    required this.onTap,
    required this.busy,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final btnSize = compact ? 48.0 : 56.0;

    Widget btn(String v, {Widget? child}) {
      final isDel = v == 'del';
      final semanticsLabel = isDel
          ? LockScreenUiCopy.deleteTooltip
          : LockScreenUiCopy.digitSemantics(v);

      return Expanded(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 3,
            vertical: compact ? 2 : 4,
          ),
          child: Center(
            child: Semantics(
              label: semanticsLabel,
              button: true,
              child: Tooltip(
                message: semanticsLabel,
                child: Material(
                  color: Colors.transparent,
                  child: InkResponse(
                    onTap: busy ? null : () => onTap(v),
                    radius: btnSize / 2 + 4,
                    containedInkWell: true,
                    highlightShape: BoxShape.circle,
                    child: Container(
                      width: btnSize,
                      height: btnSize,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      alignment: Alignment.center,
                      decoration: isDel
                          ? null
                          : BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.surfaceContainerHighest.withValues(
                                alpha: 0.4,
                              ),
                            ),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child:
                            child ??
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                v,
                                style: TextStyle(
                                  fontSize: compact ? 22 : 24,
                                  fontWeight: FontWeight.normal,
                                  color: cs.onSurface,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [btn('1'), btn('2'), btn('3')]),
          Row(children: [btn('4'), btn('5'), btn('6')]),
          Row(children: [btn('7'), btn('8'), btn('9')]),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: compact ? 2 : 4,
                  ),
                  child: Center(
                    child: SizedBox(width: btnSize, height: btnSize),
                  ),
                ),
              ),
              btn('0'),
              btn(
                'del',
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Icon(
                    Icons.backspace_outlined,
                    size: compact ? 22 : 24,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
